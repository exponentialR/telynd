# SwiftTerm release resources

These unmodified resources come from SwiftTerm 1.20.0, commit
`5d14406844143538cd8f8851d2d8a67c1fe443e5`, matching `Package.resolved`:

- `LICENSE`: the upstream MIT licence.
- `Shaders.metal`: `Sources/SwiftTerm/Apple/Metal/Shaders.metal` upstream.

The app build compares these files with the resolved dependency resources.
Release validation compares the packaged files with these committed copies,
without executing a package manifest or fetching dependencies in the signing job.
Update both copies when reviewing a SwiftTerm dependency update.
