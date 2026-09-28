# Contributing

Insomnia is one Objective-C file. Keep it that way if you can.

```sh
./build.sh          # build and install to ~/Applications
./test.sh           # run the guard matrix against the running app
```

- No dependencies. Only frameworks that ship with macOS, built with clang from the Command Line Tools.
- Every guard must be **battery only** and must never touch plain idle-sleep prevention.
- Anything that sets `pmset disablesleep 1` must have a path that sets it back to 0 on off, quit, and next launch.
- Add a debug hook (`insomnia.debug.*`) for any new external signal so `test.sh` can simulate it.
- Update `CHANGELOG.md` under a new version heading. `release.sh` refuses to tag without it.
- Open a pull request against `main`. CI builds it.
