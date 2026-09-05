---
name: shard-inspector
description: Inspect downloaded Azure Kusto Engine V3 shard data and inverted indexes, save bounded semantic output as JSON, or generate an interactive HTML B-tree visualization of decoded terms and postings. Use when the user asks to inspect or visualize a shard GUID, downloaded shard folder, .shard file, stripe data, idx_meta, idx_terms, idx_pos, indexed fields, terms, postings, positions, B-tree, or sample records.
---

# Kusto shard inspector

Use the maintained Rust `shard_inspector` from the Azure-Kusto-Service
repository. Never interpret `.shard`, `.stripe`, or `idx_*` bytes with generic
text tools, and never modify downloaded artifacts.

## Invocation

The user can invoke this skill directly:

```text
/shard-inspector show indexes and data for shard <GUID-or-path>
```

Accept any of:

- a shard GUID, resolved as `%USERPROFILE%\Downloads\<GUID>`;
- a downloaded shard directory;
- a direct `<GUID>.shard` path.

## Required workflow

1. Run the bundled script rather than assembling `cargo` commands manually:

   ```powershell
   & "<skill-directory>\scripts\Inspect-KustoShard.ps1" `
     -Shard "<GUID-or-path>"
   ```

2. Select output based on the request:

   - Indexes and data: use the defaults.
   - Indexes only: add `-IndexesOnly -RecordLimit 0`.
   - Interactive inverted-index visualization is the default. It preserves the
     JSON and also creates and opens a self-contained `.html` file.
   - JSON only: add `-NoHtml`.
   - More or fewer results: set `-RecordLimit`, `-TermLimit`, and
     `-PostingLimit`. Keep output bounded unless the user explicitly requests
     larger limits.
   - Do not open VS Code only when explicitly requested: add `-NoOpen`.

3. Report both the generated JSON source and HTML visualization paths. For a
   `-NoHtml` run, report only the JSON path.
4. Summarize:

   - shard record, field, and stripe counts;
   - indexed fields and tokenizers;
   - enumerated term and posting counts;
   - whether any section was truncated;
   - row-sampling omissions or decoding errors.

## Safe defaults

- Record samples per stripe: `20`
- Inverted-index terms: `1000`
- Posting positions across indexes: `10000`
- Output: `%USERPROFILE%\Downloads\<GUID>-shard-inspection.json`
- VS Code opens automatically.

Default invocation:

```powershell
& "<skill-directory>\scripts\Inspect-KustoShard.ps1" `
  -Shard "<GUID-or-path>" `
  -IndexesOnly `
  -RecordLimit 0
```

The default HTML path is the JSON path with an `.html` extension. The page uses
the decoder's actual ordered terms, indexed fields, tokenizers, and sampled
postings. It renders a conceptual B-tree lookup path because the stable
inspector output does not expose physical B-tree page boundaries. Never claim
that the displayed page grouping is the file's exact on-disk page structure.

`-Html` remains accepted for backward compatibility but is no longer required.
Use `-NoHtml` when only JSON output is wanted.

To visualize an existing inspector JSON without decoding the shard again:

```powershell
& "<skill-directory>\scripts\New-KustoShardBTreeHtml.ps1" `
  -JsonPath "<inspection.json>"
```

Limits are intentionally bounded. Do not set them to extremely large values
without explaining the likely output size.

## Download completeness

The expected layout is:

```text
<GUID>\
  <GUID>.shard
  <stripe-GUID>.stripe
  index\
    idx_meta_<suffix>
    idx_terms
    idx_pos
```

If any `.azDownload-*` files remain, the Storage Explorer download is not
finalized. The script stops without running the decoder. If a temporary file is
stable but exclusively locked, tell the user to inspect Storage Explorer's
Activities pane. If stalled or failed, cancel and redownload only that artifact.
Never rename a locked temporary file.

## Semantics

- `.shard`: TOC containing schema, statistics, stripe locations, tags, and
  index descriptors.
- `.stripe`: compressed column data and embedded range indexes.
- `idx_meta_*`: indexed-field and tokenizer metadata.
- `idx_terms`: inverted-index term B-tree.
- `idx_pos`: postings and optional term offsets.

The files must be decoded together through descriptor paths from the `.shard`
TOC. Azure Storage Explorer only downloads them.
`metadata_artifacts_reader` handles a different metadata family and must not be
used.

## Known limitation

The current stable `stg_shard` JSON visitor cannot render `Guid`, `Decimal`,
`TriState`, or `Null` leaves. When encountered, row samples are omitted with an
explicit reason; shard, stripe, column, and index metadata remain available.
