# asgs-lint

A very strict static ASGS configuration file checker.

## Quick Start

No options are required if `ASGS_CONFIG` is set:

  1. `./asgsh`
  2. `load profile # (select profile)` 
  3. `asgs-lint    # command is available via PATH`
  4. if `asgs-lint` finds an issue with the config it'll exit;
     fix the issue and rerun until there are no more issues
     found
## Description

Run inside of `asgsh` with a profile loaded. Without any options `ASGS_CONFIG`
is examined for required or highly recommended settings. `asgs-lint` fails
on the first problem found. Fix the problem, then run again until there
are no more issues found.

This tool is a static analysis tool; meaning it examines the text of `ASGS_CONFIG`
and any files contained therein as long as the file paths may be determined
without executing or `source`ing any shell scripts.

## Advanced Usage:

| Option                      | Meaning                                            |
| --------------------------- | ---------------------------------------------------|
| `--help`                    | This help text                                     |
| `--config path/to/config.sh`| Check a config other than `ASGS_CONFIG`            | 
| `--list vars`               | Summary of required variables and descriptions     |
| `--list disallowed`         | Summary of variables forbidden because they conflict with important environmental variables|

## Maintenance Note

This script is meant to be updated whenever new static checks
are needed; usually as a result of a long debugging session that
could have been caught using a static checker tool like this one.
