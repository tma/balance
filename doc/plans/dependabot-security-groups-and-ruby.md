# Group all Dependabot updates and track Ruby images

## Problem
Version updates are already grouped, but security updates still open one pull request per gem. Groups apply only to version updates unless `applies-to` says otherwise.

Ruby is pinned at 3.4.8 in the Dockerfiles and `.ruby-version`. `ubuntu-latest` no longer publishes that patch. Dependabot does not watch those image tags today, and the production `Dockerfile` hides the tag in `ARG RUBY_VERSION`, which the Docker parser skips.

## Proposed solution
- Add a security-updates group next to each existing version-updates group, both with `patterns: ["*"]`.
- Add a grouped `docker` entry for `/` and `/.devcontainer`.
- Put a literal tag on the production `FROM` line so Dependabot can bump Ruby. Leave the version number for Dependabot to update. Do not hand-edit `.ruby-version`; Dependabot has no ecosystem for that file.

## Files to modify
- `.github/dependabot.yml`
- `Dockerfile`
- `.devcontainer/Dockerfile` comment only, so it does not hardcode a patch Dependabot will not update

## Considerations
- CI already tracks the `3.4` line and should stay that way. A pinned patch in the workflow will 404 again the next time the runner drops it.
- After this lands, trigger a Dependabot docker update so the Ruby image bump is a Dependabot pull request.
