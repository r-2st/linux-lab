# Using the Makefile

The `Makefile` is the entry point for everything: tooling, boxes, labs, and docs. Run
`make help` for the full list. Most targets take one of three variables:

| Variable | Default | Used by |
| --- | --- | --- |
| `BOX` | `rocky-8.10` | `box`, `box-add`: a file name from `packer/vars/` without `.pkrvars.hcl` |
| `LAB` | `cert-lab` | Vagrant targets: a directory under `labs/` |
| `VM` | *(all)* | Vagrant targets: one machine in the lab, e.g. `VM=root-ca` |

## Workflow

```mermaid
flowchart LR
    subgraph machine ["1 · Once per machine"]
        direction TB
        setup["make setup<br/>uv → .venv → Galaxy → hooks"]
        readiness["make readiness<br/>Packer + KVM smoke test"]
        setup --> readiness
    end

    subgraph boxes ["2 · Once per box"]
        direction TB
        box["make box<br/>BOX=#lt;box#gt;"]
        boxadd["make box-add<br/>BOX=#lt;box#gt;"]
        all["or: make boxes<br/>build + import all"]
        box --> boxadd
        boxadd ~~~ all
    end

    subgraph lab ["3 · Lab work (LAB=, VM=)"]
        direction TB
        up["make up"]
        ssh["make ssh VM=#lt;vm#gt;"]
        provision["make provision<br/>re-run Ansible"]
        halt["make halt<br/>pause; up resumes"]
        destroy["make destroy<br/>start fresh"]
        up --> ssh --> provision
        provision ~~~ halt ~~~ destroy
    end

    subgraph change ["4 · Changing the repo"]
        direction TB
        fmt["make fmt"]
        validate["make validate"]
        run["make run<br/>all pre-commit hooks"]
        commit["git commit<br/>hooks run again"]
        ci["CI on push/PR<br/>run + validate + docs"]
        fmt --> validate --> run --> commit --> ci
    end

    machine --> boxes --> lab -. "improve the lab" .-> change
```

`make docs` previews this site while you edit, and `make update` bumps `uv.lock` and the
pre-commit hook revs. Targets that depend on others run them first: `setup` runs `install-uv`, `sync`, and `galaxy`;
`validate`, `box`, and `readiness` run `init` (Packer plugins). Every target puts the repo's
`.venv/bin` first on `PATH`, so nothing needs activating.

## Common commands

```sh
make setup                              # new clone or new machine
make box BOX=rocky-9.4 && make box-add BOX=rocky-9.4
make up LAB=cert-lab                    # all three VMs
make ssh LAB=cert-lab VM=issuing-ca
make halt LAB=cert-lab VM=root-ca       # keep the root CA offline
make destroy LAB=cert-lab && make up LAB=cert-lab   # reset the lab
```

## All targets

--8<-- "README.md:make-targets"
