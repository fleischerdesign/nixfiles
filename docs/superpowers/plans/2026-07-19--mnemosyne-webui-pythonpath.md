# Mnemosyne PYTHONPATH for Hermes WebUI — Implementation Plan
> **For agentic workers:** Execute tasks sequentially. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make `mnemosyne-memory` and `mnemosyne-hermes` Python packages available to the Hermes WebUI process so the Mnemosyne memory provider loads correctly.

**Architecture:** Extract the three custom Python package definitions (`ddgs`, `mnemosyne-memory`, `mnemosyne-hermes`) from `hermes-agent/default.nix` into a shared `python-packages.nix` alongside it. Both the agent and webui modules import this file. Add `PYTHONPATH` to the webui's `extraEnvironment` referencing the packages' site-packages.

**Tech Stack:** Nix (NixOS modules), nixfmt 1.3.1, deadnix 1.3.1

## Global Constraints
- All Nix files must pass `nixfmt` formatting
- All Nix files must pass `deadnix --fail` (no dead code)
- The `fastembed-override` stays with the agent config as a local override of an upstream package (not general-purpose)
- Existing `flake.lock` must not change
- `extraPythonPackages` in the agent config must continue to work identically

---

### Task 1: Create `features/services/hermes-agent/python-packages.nix`
**Files:**
- Create: `features/services/hermes-agent/python-packages.nix`

**Interfaces:**
- Consumes: `pkgs` (from the calling module), `pythonPackages` (via `pkgs.python312Packages`)
- Produces: Attribute set with `ddgs`, `mnemosyne-memory`, `mnemosyne-hermes` keys

- [ ] **Step 1: Create the shared package file**
  Extract the `ddgs`, `mnemosyne-memory`, and `mnemosyne-hermes` definitions from `hermes-agent/default.nix` lines 15-86 into a standalone file.

  The file takes `{ pkgs, lib }` as arguments and returns `{ ddgs, mnemosyne-memory, mnemosyne-hermes }`.

  The `fastembed-override` stays in `hermes-agent/default.nix` — it's a local override of an existing nixpkgs package (`pkgs.python312Packages.fastembed`) and is not a standalone package. However, `mnemosyne-memory`'s `propagatedBuildInputs` needs to reference it. Solution: keep `fastembed-override` in `hermes-agent/default.nix` and pass it as an argument to `python-packages.nix`.

  API design:
  ```nix
  # features/services/hermes-agent/python-packages.nix
  { pkgs, lib, fastembed-override ? pkgs.python312Packages.fastembed }:
  let
    pythonPackages = pkgs.python312Packages;
  in
  {
    # ddgs, mnemosyne-memory, mnemosyne-hermes definitions
  }
  ```

- [ ] **Step 2: Verify the file parses**
  ```bash
  cd /tmp/nixfiles && nix-instantiate --eval --strict features/services/hermes-agent/python-packages.nix 2>&1 | head -5
  ```

- [ ] **Step 3: Commit**
  ```bash
  git add features/services/hermes-agent/python-packages.nix
  git commit -m "feat(hermes-agent): extract python packages into shared module"
  ```

---

### Task 2: Update `hermes-agent/default.nix`
**Files:**
- Modify: `features/services/hermes-agent/default.nix`

**Interfaces:**
- Consumes: `python-packages.nix` (via import with `fastembed-override`)
- Produces: Same `extraPythonPackages` list as before, but via imported packages

- [ ] **Step 1: Import `python-packages.nix` and remove local definitions**
  In the `let` block of `default.nix`:
  - Remove the `ddgs`, `mnemosyne-memory`, `mnemosyne-hermes` definitions
  - Keep `fastembed-override` (it's a local override of `pkgs.python312Packages.fastembed`)
  - Add: `hermesPkgs = import ./python-packages.nix { inherit pkgs lib; fastembed-override = fastembed-override; };`
  - Update `extraPythonPackages` to: `[ hermesPkgs.mnemosyne-hermes hermesPkgs.mnemosyne-memory hermesPkgs.ddgs ]`
  - Update the bootstrap service's `ExecStart` to use `${hermesPkgs.mnemosyne-hermes}/bin/mnemosyne-hermes`

- [ ] **Step 2: Verify the file parses**
  ```bash
  cd /tmp/nixfiles && nix-instantiate --eval --strict features/services/hermes-agent/default.nix 2>&1 | tail -5
  ```

- [ ] **Step 3: Commit**
  ```bash
  git add features/services/hermes-agent/default.nix
  git commit -m "refactor(hermes-agent): reference packages from shared module"
  ```

---

### Task 3: Update `hermes-webui/default.nix`
**Files:**
- Modify: `features/services/hermes-webui/default.nix`

**Interfaces:**
- Consumes: `python-packages.nix` (for `PYTHONPATH`)
- Produces: WebUI service with `PYTHONPATH` containing mnemosyne packages

- [ ] **Step 1: Import packages and add PYTHONPATH**
  In the `let` block:
  - Add: `hermesPkgs = import ../hermes-agent/python-packages.nix { inherit pkgs lib; };`
  - In `extraEnvironment`, add:
    ```nix
    PYTHONPATH = lib.mkBefore (
      "${hermesPkgs.mnemosyne-hermes}/${pkgs.python3.sitePackages}:${hermesPkgs.mnemosyne-memory}/${pkgs.python3.sitePackages}"
    );
    ```
  - Also add `ddgs` if the WebUI needs it (check if it's used — `ddgs` is a DuckDuckGo search package for the agent, likely not needed by WebUI. Omit it.)

- [ ] **Step 2: Verify the file parses**
  ```bash
  cd /tmp/nixfiles && nix-instantiate --eval --strict features/services/hermes-webui/default.nix 2>&1 | tail -5
  ```

- [ ] **Step 3: Commit**
  ```bash
  git add features/services/hermes-webui/default.nix
  git commit -m "fix(hermes-webui): add mnemosyne packages to PYTHONPATH"
  ```

---

### Task 4: Format & Lint
**Files:**
- All modified files in `features/services/hermes-agent/` and `features/services/hermes-webui/`

- [ ] **Step 1: Run nixfmt**
  ```bash
  cd /tmp/nixfiles && nix develop -c nixfmt features/services/hermes-agent/python-packages.nix features/services/hermes-agent/default.nix features/services/hermes-webui/default.nix
  ```

- [ ] **Step 2: Run deadnix**
  ```bash
  cd /tmp/nixfiles && nix develop -c deadnix --fail features/services/hermes-agent/default.nix features/services/hermes-agent/python-packages.nix features/services/hermes-webui/default.nix
  ```

- [ ] **Step 3: Commit formatting**
  ```bash
  git add -A
  git commit -m "style: format with nixfmt, lint with deadnix"
  ```

---

### Task 5: Create Pull Request
**Files:**
- Git operations only

- [ ] **Step 1: Check current branch and create PR**
  ```bash
  cd /tmp/nixfiles
  git remote -v
  gh pr create --title "fix(hermes-webui): add mnemosyne packages to WebUI PYTHONPATH" --body "..."
  ```
