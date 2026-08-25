# artoo: Lossless CDISC-Native Input and Output for Clinical Datasets

Reads and writes clinical-trial datasets losslessly across 'SAS' XPORT
(XPT), Clinical Data Interchange Standards Consortium (CDISC)
Dataset-JSON, and 'Apache Parquet', applying a specification to produce
submission-ready Study Data Tabulation Model (SDTM) and Analysis Data
Model (ADaM) datasets. A single canonical metadata model carries labels,
CDISC data types, lengths, 'SAS' display formats, controlled-terminology
references, and sort keys identically across every format, so conversion
between any two formats is lossless by construction. Pure 'R' and
lightweight, with no external 'SAS' or 'Java' runtime. Reads and writes
CDISC Define-XML, the specification document that accompanies a
submission, and renders it as HTML through the bundled Define-XML
stylesheet. Implements the published format specifications for CDISC
Dataset-JSON
(<https://cdisc-org.github.io/DataExchange-DatasetJson/doc/dataset-json1-1.html>),
CDISC Define-XML
(<https://www.cdisc.org/standards/data-exchange/define-xml>), and 'SAS'
XPORT
(<https://www.loc.gov/preservation/digital/formats/fdd/fdd000466.shtml>).

## See also

Useful links:

- <https://vthanik.github.io/artoo/>

- <https://github.com/vthanik/artoo>

- Report bugs at <https://github.com/vthanik/artoo/issues>

## Author

**Maintainer**: Vignesh Thanikachalam <about.vignesh@gmail.com>
\[copyright holder\]

Authors:

- Vignesh Thanikachalam <about.vignesh@gmail.com> \[copyright holder\]

Other contributors:

- Lex Jansen (Author of the bundled CDISC Define-XML stylesheets)
  \[copyright holder\]

- Clinical Data Interchange Standards Consortium (CDISC) (Author of the
  bundled Define-XML, ODM and ARM schemas and example documents)
  \[copyright holder\]

- World Wide Web Consortium (Author of the bundled xml, xlink and
  xmldsig schemas) \[copyright holder\]
