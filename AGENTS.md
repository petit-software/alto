# Working on Alto

## Required handoff

- After every batch of app changes, rebuild, reinstall to `/Applications/Alto.app`,
  and relaunch the installed app before handing back to the user. Run
  `./scripts/install-app.sh`; do not leave the user running an older build or
  ask them to reopen it themselves. Verify the installed process is running.
- Keep installation/relaunch silent: never trigger demo speech or audible tests.
- If installation or launch fails, report the actual blocker; do not claim it ran.

## Verification rules

- Keep automated verification silent. `swift test`, `--audio-regression`, and
  `--integration-test` without `--audible-playback` are the normal checks.
- Run audible tests only when the user explicitly requests or approves them
  for the current task. Never change system volume, audio devices, or another
  app's microphone settings to make a test pass.
- Generation success, finite samples, and playback completion do not establish
  sound quality. Run the longer speech fixtures and exact convolution checks;
  distinguish numerical results from human listening acceptance in reports.
- Preserve the worker-local Float32/TF32 safeguards. They prevent a reproduced
  MLX 0.30.2 NAX defect on M5. Do not remove them as duplicate configuration or
  upgrade one dependency in isolation. See `docs/audio-noise-investigation.md`.
- Investigate core reading failures before UI polish. Treat device explanations
  as hypotheses until evidence isolates the cause.
- Update `.ultra/todo.md` with actual completion and remaining checks. A skipped
  test is not a pass; permission-dependent UI checks remain explicitly pending.

## Commands

```sh
swift test
./scripts/build-app.sh
```

For existing isolated test models, both commands below are silent:

```sh
dist/Alto.app/Contents/MacOS/Alto --integration-test /private/tmp/alto-transfer-check --offline
dist/Alto.app/Contents/MacOS/Alto --audio-regression /private/tmp/alto-transfer-check
```

Do not use the user's model directory as the integration-test root. Tests may
write fixtures and installation artifacts there. See `docs/verification.md`
for setup and network-denied verification.
