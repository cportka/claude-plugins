<!-- Thanks for contributing to Portka Tools. Keep the suite green and the version story honest. -->

## Summary

<!-- What changed and why. Link any feedback issue (Closes #N). -->

## Release checklist

- [ ] Bumped `version` in `.claude-plugin/plugin.json` for **each** plugin whose files changed
      (CI's `version-bump-guard` enforces this).
- [ ] Added a `## [x.y.z]` entry to `CHANGELOG.md` for the new version (CI checks every plugin
      version has a matching heading).
- [ ] Updated the README plugin-table row(s) and the header **Version:** line to match.
- [ ] Ran `bash tests/run-tests.sh` locally → 0 failures (or relied on CI).
- [ ] Preserved existing script comments; annotated new/changed lines.

<!-- Tag + GitHub Release happen after merge: `git tag -a vX.Y.Z -m "…" && git push origin vX.Y.Z`
     (release.yml then publishes notes from the CHANGELOG section). See RELEASING.md. -->
