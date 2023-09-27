<div align="center">
	<img src="assets/zap.png" width="128" height="128" />
  <h6><i><a href="https://www.flaticon.com/free-icons/comic" title="logo">Logo created by Freepik - Flaticon</a></i></h6>
  <h3>Another [insert blazing fast synonyms] JavaScript package manager</h3>
  <a href="https://github.com/elbywan/zap/actions/workflows/build.yml?query=branch%3Amain+workflow%3ABuild"><img alt="Build Status" src="https://github.com/elbywan/zap/actions/workflows/build.yml/badge.svg"></a>
  <a href="https://www.npmjs.com/package/@zap.org/zap"><img alt="GitHub tag (latest SemVer)" src="https://img.shields.io/npm/v/@zap.org/zap"></a>
  <a href="https://github.com/elbywan/zap/blob/main/LICENSE"><img alt="GitHub" src="https://img.shields.io/github/license/elbywan/zap"></a>
</div>

---

<div align="center">

![demo](assets/demo.gif)

**`Zap` is a JavaScript package manager _(think npm/pnpm/yarn)_ that aims to be quick, reliable, memory efficient and developer friendly.**

</div>

---

### Disclaimer

Zap is a **hobby** project that I am currently working on in my free time. Documentation is sparse, Windows support is partial at best and the code is not yet ready for production.

I am not looking for contributors at the moment, but feel free to open an issue if you have any question or suggestion.

> [!WARNING]
> **Use it at your own risk.**

## Installation

```bash
npm i -g @zap.org/zap
zap --help
```

## Commands

| Command       | Aliases               | Description                                            | Status  |
| ------------- | --------------------- | ------------------------------------------------------ | ------- |
| `zap install` | `i` `add`             | Install dependencies                                   | ✅       |
| `zap remove`  | `rm` `uninstall` `un` | Remove dependencies                                    | ✅       |
| `zap init`    | `create`              | Create a new project or initialize a package.json file | ✅       |
| `zap dlx`     | `x`                   | Execute a command in a temporary environment           | ✅       |
| `zap store`   | `s`                   | Manage the store                                       | ✅       |
| `zap run`     | `r`                   | Run a script defined in package.json                   | ✅       |
| `zap rebuild` | `rb`                  | Rebuild installed native node addons                   | ✅       |
| `zap exec`    | `e`                   | Execute a shell command in the scope of the project    | ✅       |
| `zap update`  | `up` `upgrade`        | Update the lockfile with the newest package versions   | ⏳ _WIP_ |
| `zap why`     | `y`                   | Show information about why a package is installed      | ✅       |

#### Check the [project board](https://github.com/users/elbywan/projects/1/views/1) for the current status of the project.

## Features

Here is a non exhaustive list of features that are currently implemented:

- **Classic (npm-like) or isolated (pnpm-like) install strategies**

```bash
# Classic install by default
zap i # or zap i --classic
# Isolated install
zap i --isolated
```

_or:_

```json
"zap": {
  "strategy": "isolated",
  "hoist_patterns": [
    "react*"
  ],
  "public_hoist_patterns": [
    "*eslint*", "*prettier*"
  ]
}
// package.json
```

- **[Workspaces](https://docs.npmjs.com/cli/v9/using-npm/workspaces?v=true#defining-workspaces)**

```json
"workspaces": [
  "core/*",
  "packages/*"
]
// package.json
```

_or to prevent hoisting:_

```json
"workspaces": {
  "packages": [
    "packages/**"
  ],
  "nohoist": [
    "react",
    "react-dom",
    "*babel*"
  ]
}
// package.json
```

```bash
# Install all workspaces
zap i
# Using pnpm-flavored filters (see: https://pnpm.io/filtering)
zap i -F "./libs/**" -F ...@my/package...[origin/develop]
zap i -w add pkg

## Scripts can be scoped too

# Run a single script in the current workspace.
zap run my-script
# Run scripts in all workspaces in parallel.
# Will use topological ordering by default - dependencies will run first…
zap -r run test
# …or omit the "run" argument.
zap -r test
# Scope to the dependencies of a specific workspace, and pack the output.
zap -F "my_app^..." --deferred-output run build
# Disregard the topological ordering and run the scripts in parallel.
zap run --parallel -r build
```

- **[Private registries](https://docs.npmjs.com/cli/v10/configuring-npm/npmrc#auth-related-configuration)**

```ini
; .npmrc file

; default registry:
registry=https://registry.yarnpkg.com/
; scoped registries:
@myorg:registry=https://somewhere-else.com/myorg
@another:registry=https://somewhere-else.com/another
; scoped authentication: (supported fields -> _auth, _authToken, certfile, keyfile)
//registry.org/:_auth=BASICAUTHTOKEN
//registry.npmjs.org/:_authToken=BEARERTOKEN
; disable strict ssl peers checking: (default is true)
strict_ssl=false
; use a custom certificate authority file:
cafile=/certs/rootCA.crt
```

- **[Overrides](https://docs.npmjs.com/cli/v9/configuring-npm/package-json?v=true#overrides) / [Package Extensions](https://pnpm.io/package_json#pnpmpackageextensions)**

```json
"overrides": {
  "foo": {
    ".": "1.0.0",
    "bar": "1.0.0"
  }
},
"zap": {
  "package_extensions": {
    "react-redux@1": {
      "peerDependencies": {
        "react-dom": "*"
      }
    }
  }
}
// package.json
```

- **[Aliases](https://github.com/npm/rfcs/blob/main/implemented/0001-package-aliases.md)**

```bash
zap i my-react@npm:react
zap i jquery2@npm:jquery@2
zap i jquery3@npm:jquery@3
```

## Why?

**This is a legitimate question.** There are already a lot of package managers out there, and they all have their own pros and cons. So why another one?

First, I thought that it would be a good and fun challenge to build a package manager from scratch. I also really like the [Crystal language](https://crystal-lang.org/) and I have been using it for a couple of years now. So it would be a good opportunity to put my knowledge to the test.

I also experimented with a lot of package managers over the years, and I have a few praise and gripes with the existing ones:

- [npm](https://www.npmjs.com/) is the de facto standard for JavaScript package management. It is reliable and has a huge community. But it is also super slow and lack features introduced by other package managers over time even though it is trying to catch up.

- [yarn](https://yarnpkg.com/) is a great alternative to npm, it was a pioneer initially in terms of speed and it introduced many improvements and innovations along the years. Yarn is also impressively reliable which is paramount. I never used yarn berry in a significant project but the PnP approach is very interesting - unfortunately the downside is that does not seem to be compatible out of the box with a lot of packages from the ecosystem.

- [pnpm](https://pnpm.io/) is an impressive package manager which introduced the concept of isolated installs. It handles workspaces very well with a lot of options to customize the behavior. Speed is mostly fine even with big monorepos. I experienced some reliability issues using it over the years though (peer dependencies handling, lockfile inconsistencies, very high memory consumption, need to manually delete the node modules folder…).

- [bun](https://bun.sh/) was a great source of inspiration for this project, but it comes with tradeoffs. While tremendously fast, it did not support some critical features when I started working on zap (and it still is very feature-limited), cannot be considered reliable as of today and is not as flexible as I would like it to be.

- newer contenders ([orogene](https://github.com/orogene/orogene), [cotton](https://github.com/danielhuang/cotton), [ultra](https://github.com/nachoaldamav/ultra)…) are kind of interesting but they are clearly lacking in terms of features and/or reliability and/or speed.

#### So I decided to build a package manager that would be fast, flexible and easy to use. For my own personal use, but also for the community (in the long run).

### How?

Zap is written in [Crystal](https://crystal-lang.org/) which is a compiled language, which means that it should be faster than JavaScript. It can easily tap into system calls and use the fastest ones depending on the platform (_for instance [clonefile](https://www.manpagez.com/man/2/clonefile/)_). It is also an excellent fit when dealing with concurrent tasks.

Crystal also has _experimental_ support for parallelism and can dispatch fibers to a pool of worker threads, which means that zap can take advantage of multiple cores. This is especially useful when dealing with CPU-bound tasks.

On top of that, zap will also try to cache package manifests in order to avoid unnecessary network calls in a performant way using [messagepack](https://msgpack.org/).

## Development

### Prerequisites

- [Install crystal](https://crystal-lang.org/install/)
- _(optional)_ Install the [vscode extension](https://marketplace.visualstudio.com/items?itemName=crystal-lang-tools.crystal-lang) and [crystalline](https://github.com/elbywan/crystalline)

### Setup

```bash
git clone https://github.com/elbywan/zap
shards install
# Run the specs
crystal spec
# Build locally (-Dpreview_mt might not work on some os/arch)
shards build --progress -Dpreview_mt --release
```

## Contributing

1. Fork it (<https://github.com/elbywan/zap/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Julien Elbaz](https://github.com/your-github-user) - creator and maintainer

## Related

- [pnpm](https://pnpm.io/)
- [bun](https://bun.sh/)
- [npm](https://www.npmjs.com/)
- [yarn](https://yarnpkg.com/)
