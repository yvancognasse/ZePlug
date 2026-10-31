# ZePlug

iOS application project. Open `MaRecharge.xcodeproj` in Xcode; source code and assets are in `MaRecharge`. See `LISEZ-MOI.txt` and `VALIDATION.txt` for project notes. Local device builds and signing profiles under `work` are excluded.

## Source repository

Public repository: [ZePlug](https://github.com/yvancognasse/ZePlug). This local folder remains the development/build checkout. Git history starts with the current imported source snapshot; earlier local builds are not reconstructed as historical commits.

After authorized changes, run the project checks and update documentation as required in `AGENTS.md`, then commit and push to `origin/main`. Changes reach GitHub when a push succeeds, not automatically on every file save. Generated applications, caches, logs and local secrets are excluded by `.gitignore`.

```sh
git pull --ff-only
# Make and verify the change
git add .
git commit -m "Describe the change"
git push origin main
```
