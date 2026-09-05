[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $JsonPath,

    [string] $OutputPath,

    [switch] $NoOpen
)

$ErrorActionPreference = 'Stop'

$JsonPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    [Environment]::ExpandEnvironmentVariables($JsonPath)
)
if (-not (Test-Path -LiteralPath $JsonPath -PathType Leaf)) {
    throw "Shard inspection JSON does not exist: $JsonPath"
}

$json = Get-Content -LiteralPath $JsonPath -Raw
try {
    $null = $json | ConvertFrom-Json
} catch {
    throw "Shard inspection JSON is invalid: $($_.Exception.Message)"
}

if (-not $OutputPath) {
    $OutputPath = [IO.Path]::ChangeExtension($JsonPath, '.html')
} else {
    $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        [Environment]::ExpandEnvironmentVariables($OutputPath)
    )
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$dataBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
$sourceName = [Net.WebUtility]::HtmlEncode([IO.Path]::GetFileName($JsonPath))

$html = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Kusto shard inverted-index explorer</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #07111f;
      --panel: #0d1b2d;
      --panel2: #142943;
      --border: #294765;
      --text: #e8f1fb;
      --muted: #91a9c1;
      --blue: #58b7ff;
      --green: #55d69e;
      --yellow: #ffc857;
      --pink: #f58bc3;
      --line: #456886;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background:
        radial-gradient(circle at 12% 0%, #163c67 0, transparent 34rem),
        linear-gradient(155deg, var(--bg), #0a1b2d 70%, #07111f);
      color: var(--text);
      font: 14px/1.5 "Segoe UI", system-ui, sans-serif;
    }
    header {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 22px;
      align-items: end;
      padding: 25px 30px 18px;
      border-bottom: 1px solid var(--border);
      background: rgb(7 17 31 / 75%);
      backdrop-filter: blur(12px);
    }
    h1 { margin: 0; font-size: clamp(22px, 3vw, 33px); }
    h2 { margin: 0 0 9px; font-size: 17px; }
    p { margin: 5px 0; }
    code { color: #b9ddff; font-family: Consolas, monospace; }
    .muted { color: var(--muted); }
    .controls { display: grid; grid-template-columns: 140px minmax(230px, 1fr) auto; gap: 8px; }
    select, input, button {
      height: 39px;
      min-width: 0;
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 0 11px;
      color: var(--text);
      background: var(--panel2);
      font: inherit;
    }
    button { cursor: pointer; background: #1263a2; border-color: #2587d0; }
    button:hover { background: #1979c1; }
    main {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 350px;
      gap: 18px;
      padding: 22px 30px 30px;
    }
    .canvas, aside section {
      border: 1px solid var(--border);
      border-radius: 14px;
      background: rgb(13 27 45 / 88%);
      box-shadow: 0 18px 55px rgb(0 0 0 / 24%);
    }
    .canvas { position: relative; min-height: 700px; overflow: auto; padding: 24px; }
    .tree { position: relative; z-index: 1; min-width: 900px; }
    .level { display: grid; gap: 20px; align-items: start; margin-bottom: 88px; }
    .root-level { grid-template-columns: 290px; justify-content: center; }
    .branch-level { grid-template-columns: repeat(3, 230px); justify-content: space-around; }
    .leaf-level { grid-template-columns: repeat(6, minmax(130px, 1fr)); gap: 12px; margin-bottom: 28px; }
    .node {
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 12px;
      background: linear-gradient(145deg, #17304e, #0d1d30);
      box-shadow: 0 8px 20px rgb(0 0 0 / 22%);
      transition: opacity 160ms, border-color 160ms, transform 160ms;
    }
    .node.root { border-top: 4px solid var(--yellow); }
    .node.branch { border-top: 4px solid var(--blue); }
    .node.leaf { border-top: 4px solid var(--green); }
    .node.dim { opacity: .24; }
    .node.active {
      border-color: var(--yellow);
      box-shadow: 0 0 0 2px rgb(255 200 87 / 25%), 0 8px 26px rgb(255 200 87 / 18%);
      transform: translateY(-3px);
    }
    .node-title {
      display: flex;
      justify-content: space-between;
      gap: 6px;
      margin-bottom: 7px;
      color: var(--muted);
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: .08em;
    }
    .keys { display: flex; flex-wrap: wrap; gap: 5px; }
    .key { border-radius: 5px; padding: 4px 7px; background: #1d3e61; font: 12px Consolas, monospace; }
    .term {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 5px;
      padding: 5px 2px;
      border-bottom: 1px solid rgb(69 104 134 / 42%);
      font: 11px Consolas, monospace;
    }
    .term:last-child { border-bottom: 0; }
    .term-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .term-count { color: var(--pink); }
    .term.found {
      margin-inline: -5px;
      padding-inline: 5px;
      border-radius: 4px;
      color: #071810;
      background: var(--green);
      font-weight: 700;
    }
    .term.found .term-count { color: #16513b; }
    svg { position: absolute; inset: 24px; z-index: 0; min-width: 900px; pointer-events: none; overflow: visible; }
    line { stroke: var(--line); stroke-width: 2; transition: opacity 160ms, stroke 160ms; }
    line.dim { opacity: .16; }
    line.active { stroke: var(--yellow); stroke-width: 4; }
    .postings {
      border: 1px dashed #624d78;
      border-radius: 10px;
      padding: 16px;
      background: #171426;
    }
    .posting {
      margin: 8px 0 0;
      padding: 9px;
      border-radius: 7px;
      background: #251d35;
      font: 12px Consolas, monospace;
      overflow-wrap: anywhere;
    }
    .position {
      display: inline-block;
      margin: 5px 4px 0 0;
      padding: 3px 7px;
      border-radius: 99px;
      color: #ffd9ed;
      background: #4b2d57;
    }
    aside { display: grid; gap: 15px; align-content: start; }
    aside section { padding: 17px; }
    .metric-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
    .metric { border-radius: 8px; padding: 9px; background: var(--panel2); }
    .metric strong { display: block; font-size: 18px; color: var(--green); }
    .callout { border-left: 3px solid var(--yellow); padding-left: 11px; color: #eadba9; }
    .field-list { max-height: 220px; overflow: auto; padding-left: 20px; }
    .field-list li { margin-bottom: 5px; overflow-wrap: anywhere; }
    @media (max-width: 1050px) {
      header { grid-template-columns: 1fr; }
      main { grid-template-columns: 1fr; padding-inline: 14px; }
      aside { grid-template-columns: repeat(auto-fit, minmax(270px, 1fr)); }
    }
  </style>
</head>
<body>
  <header>
    <div>
      <h1><code>idx_terms</code> explorer</h1>
      <p class="muted">Decoded terms and postings from <code>__SOURCE__</code>. Page grouping is conceptual.</p>
    </div>
    <div class="controls">
      <select id="indexSelect" aria-label="Inverted index"></select>
      <input id="termInput" list="termList" aria-label="Term" placeholder="Choose or type a decoded term">
      <datalist id="termList"></datalist>
      <button id="findButton" type="button">Find term</button>
    </div>
  </header>
  <main>
    <section class="canvas" id="canvas">
      <svg id="edges" aria-hidden="true"></svg>
      <div class="tree">
        <div class="level root-level" id="rootLevel"></div>
        <div class="level branch-level" id="branchLevel"></div>
        <div class="level leaf-level" id="leafLevel"></div>
        <div class="postings">
          <h2><code>idx_pos</code> decoded postings</h2>
          <div id="postings"></div>
        </div>
      </div>
    </section>
    <aside>
      <section>
        <h2>Selected index</h2>
        <div class="metric-grid">
          <div class="metric"><span class="muted">Total terms</span><strong id="totalTerms">0</strong></div>
          <div class="metric"><span class="muted">Decoded sample</span><strong id="sampleTerms">0</strong></div>
          <div class="metric"><span class="muted">Positions</span><strong id="positionCount">0</strong></div>
          <div class="metric"><span class="muted">Tokenizer</span><strong id="tokenizer">—</strong></div>
        </div>
      </section>
      <section>
        <h2>Lookup</h2>
        <p id="lookup" class="callout"></p>
        <p class="muted">The highlighted route explains B-tree navigation. The inspector exposes ordered terms and postings, but not physical B-tree page boundaries.</p>
      </section>
      <section>
        <h2>Indexed fields</h2>
        <ol id="fields" class="field-list"></ol>
      </section>
    </aside>
  </main>
  <script>
    const encoded = "__DATA_BASE64__";
    const decoded = new TextDecoder().decode(Uint8Array.from(atob(encoded), c => c.charCodeAt(0)));
    const report = JSON.parse(decoded.replace(/^\uFEFF/, ""));
    const indexes = Array.isArray(report)
      ? report
      : (Array.isArray(report.inverted_indexes) ? report.inverted_indexes : [report]);
    const indexSelect = document.getElementById("indexSelect");
    const termInput = document.getElementById("termInput");
    const termList = document.getElementById("termList");
    const canvas = document.getElementById("canvas");
    const svg = document.getElementById("edges");
    let currentIndex = null;
    let visibleTerms = [];
    let selectedTerm = null;

    function label(term) {
      return term.term_utf8 ?? `0x${term.term_hex ?? ""}`;
    }

    function postingCount(term) {
      return (term.postings ?? []).reduce((sum, posting) => sum + (posting.positions?.length ?? 0), 0);
    }

    function compact(value, max = 18) {
      return value.length <= max ? value : `${value.slice(0, max - 1)}…`;
    }

    function selectWindow(terms, selected) {
      const limit = 24;
      if (terms.length <= limit) return terms.slice();
      const selectedIndex = Math.max(0, terms.indexOf(selected));
      let start = Math.max(0, selectedIndex - Math.floor(limit / 2));
      start = Math.min(start, terms.length - limit);
      return terms.slice(start, start + limit);
    }

    function partition(items, count) {
      const result = [];
      for (let i = 0; i < count; i++) {
        const start = Math.floor(i * items.length / count);
        const end = Math.floor((i + 1) * items.length / count);
        result.push(items.slice(start, Math.max(end, start + (start < items.length ? 1 : 0))));
      }
      return result;
    }

    function node(id, type, title, range, keys) {
      return `<div class="node ${type}" id="${id}">
        <div class="node-title"><span>${title}</span><span>${range}</span></div>
        <div class="keys">${keys.map(key => `<span class="key" title="${escapeHtml(key)}">${escapeHtml(compact(key))}</span>`).join("")}</div>
      </div>`;
    }

    function escapeHtml(value) {
      return String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
    }

    function renderTree() {
      const terms = currentIndex.terms ?? [];
      selectedTerm = terms.find(term => label(term) === termInput.value) ?? terms[0] ?? null;
      if (!selectedTerm) {
        document.getElementById("rootLevel").innerHTML = "";
        document.getElementById("branchLevel").innerHTML = "";
        document.getElementById("leafLevel").innerHTML = "<p>No decoded terms are available.</p>";
        document.getElementById("postings").innerHTML = "<p>No postings are available.</p>";
        return;
      }

      termInput.value = label(selectedTerm);
      visibleTerms = selectWindow(terms, selectedTerm);
      const leaves = partition(visibleTerms, 6);
      const branches = [leaves.slice(0, 2), leaves.slice(2, 4), leaves.slice(4, 6)];
      const rootKeys = branches.slice(1).map(group => label(group[0][0]));

      document.getElementById("rootLevel").innerHTML =
        node("root", "root", "Conceptual root", "separator terms", rootKeys);

      document.getElementById("branchLevel").innerHTML = branches.map((group, index) => {
        const keys = group.slice(1).map(leaf => label(leaf[0]));
        return node(`branch-${index}`, "branch", `Conceptual internal ${index + 1}`, "routing", keys);
      }).join("");

      document.getElementById("leafLevel").innerHTML = leaves.map((leaf, leafIndex) => {
        const rows = leaf.map(term => {
          const found = term === selectedTerm ? " found" : "";
          return `<div class="term${found}" title="${escapeHtml(label(term))}">
            <span class="term-name">${escapeHtml(label(term))}</span>
            <span class="term-count">${postingCount(term)} pos</span>
          </div>`;
        }).join("");
        return `<div class="node leaf" id="leaf-${leafIndex}">
          <div class="node-title"><span>Conceptual leaf ${leafIndex + 1}</span><span>ordered terms</span></div>
          ${rows}
        </div>`;
      }).join("");

      const selectedLeaf = leaves.findIndex(leaf => leaf.includes(selectedTerm));
      const selectedBranch = Math.floor(selectedLeaf / 2);
      requestAnimationFrame(() => {
        drawEdges();
        highlight(selectedBranch, selectedLeaf);
      });
      renderPostings(selectedTerm);
      document.getElementById("lookup").innerHTML =
        `<code>${escapeHtml(label(selectedTerm))}</code> → root → internal ${selectedBranch + 1} → leaf ${selectedLeaf + 1} → <code>idx_pos</code>`;
    }

    function renderPostings(term) {
      const postings = term.postings ?? [];
      document.getElementById("postings").innerHTML = postings.length
        ? postings.map(posting => {
            const positions = (posting.positions ?? []).map(position =>
              `<span class="position">${escapeHtml(position)}</span>`).join("");
            const truncated = posting.positions_truncated ? " · positions truncated" : "";
            return `<div class="posting">
              stripe ${escapeHtml(posting.stripe)} · ${escapeHtml(posting.field ?? "unknown field")}
              · field positions ${Number(posting.field_position_count ?? 0).toLocaleString()}${truncated}
              <div>${positions || '<span class="muted">No sampled positions</span>'}</div>
            </div>`;
          }).join("")
        : '<p class="muted">No decoded postings for this term.</p>';
    }

    function centerBottom(element) {
      const box = element.getBoundingClientRect();
      const host = canvas.getBoundingClientRect();
      return { x: box.left - host.left + box.width / 2 + canvas.scrollLeft, y: box.bottom - host.top + canvas.scrollTop };
    }

    function centerTop(element) {
      const box = element.getBoundingClientRect();
      const host = canvas.getBoundingClientRect();
      return { x: box.left - host.left + box.width / 2 + canvas.scrollLeft, y: box.top - host.top + canvas.scrollTop };
    }

    function drawLine(fromId, toId) {
      const from = centerBottom(document.getElementById(fromId));
      const to = centerTop(document.getElementById(toId));
      const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
      line.id = `${fromId}-${toId}`;
      line.setAttribute("x1", from.x - 24);
      line.setAttribute("y1", from.y - 24);
      line.setAttribute("x2", to.x - 24);
      line.setAttribute("y2", to.y - 24);
      svg.appendChild(line);
    }

    function drawEdges() {
      svg.innerHTML = "";
      svg.setAttribute("width", Math.max(canvas.scrollWidth, 940));
      svg.setAttribute("height", canvas.scrollHeight);
      for (let branch = 0; branch < 3; branch++) {
        drawLine("root", `branch-${branch}`);
        drawLine(`branch-${branch}`, `leaf-${branch * 2}`);
        drawLine(`branch-${branch}`, `leaf-${branch * 2 + 1}`);
      }
    }

    function highlight(branchIndex, leafIndex) {
      const activeNodes = new Set(["root", `branch-${branchIndex}`, `leaf-${leafIndex}`]);
      const activeEdges = new Set([`root-branch-${branchIndex}`, `branch-${branchIndex}-leaf-${leafIndex}`]);
      document.querySelectorAll(".node").forEach(element => {
        element.classList.toggle("active", activeNodes.has(element.id));
        element.classList.toggle("dim", !activeNodes.has(element.id));
      });
      document.querySelectorAll("line").forEach(element => {
        element.classList.toggle("active", activeEdges.has(element.id));
        element.classList.toggle("dim", !activeEdges.has(element.id));
      });
    }

    function loadIndex(index) {
      currentIndex = indexes[index];
      const terms = currentIndex.terms ?? [];
      termList.innerHTML = terms.map(term => `<option value="${escapeHtml(label(term))}"></option>`).join("");
      termInput.value = terms[0] ? label(terms[0]) : "";
      document.getElementById("totalTerms").textContent = Number(currentIndex.term_count ?? currentIndex.descriptor?.term_count ?? 0).toLocaleString();
      document.getElementById("sampleTerms").textContent = terms.length.toLocaleString();
      document.getElementById("positionCount").textContent = Number(currentIndex.descriptor?.pos_count ?? 0).toLocaleString();
      document.getElementById("tokenizer").textContent = currentIndex.descriptor?.tokenizer ?? "—";
      document.getElementById("fields").innerHTML = (currentIndex.indexed_fields ?? []).map(field =>
        `<li><code>${escapeHtml(field.field)}</code><br><span class="muted">${escapeHtml(field.tokenizer)}</span></li>`
      ).join("");
      renderTree();
    }

    indexes.forEach((index, ordinal) => {
      const option = document.createElement("option");
      option.value = ordinal;
      option.textContent = `Index ${index.ordinal ?? ordinal}`;
      indexSelect.appendChild(option);
    });
    indexSelect.addEventListener("change", () => loadIndex(Number(indexSelect.value)));
    document.getElementById("findButton").addEventListener("click", renderTree);
    termInput.addEventListener("keydown", event => {
      if (event.key === "Enter") renderTree();
    });
    window.addEventListener("resize", drawEdges);
    loadIndex(0);
  </script>
</body>
</html>
'@

$html = $html.Replace('__DATA_BASE64__', $dataBase64).Replace('__SOURCE__', $sourceName)
Set-Content -LiteralPath $OutputPath -Value $html -Encoding utf8

if (-not $NoOpen) {
    Start-Process -FilePath $OutputPath
}

Write-Output $OutputPath
