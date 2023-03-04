<div align="center">
	<img src="assets/zap.png" width="128" height="128" />
  <h6><i><a href="https://www.flaticon.com/free-icons/comic" title="logo">Logo created by Freepik - Flaticon</a></i></h6>
	<h1>zap</h1>
  <h3>Another [insert blazing synonyms] JavaScript package manager</h3>
  <a href="https://github.com/elbywan/zap/actions/workflows/build.yml?query=branch%3Amain+workflow%3ABuild"><img alt="Build Status" src="https://github.com/elbywan/zap/actions/workflows/build.yml/badge.svg"></a>
  <a href="https://www.npmjs.com/package/@zap.org/zap"><img alt="GitHub tag (latest SemVer)" src="https://img.shields.io/npm/v/@zap.org/zap"></a>
  <a href="https://github.com/elbywan/crystalline/blob/main/LICENSE"><img alt="GitHub" src="https://img.shields.io/github/license/elbywan/crystalline"></a>
</div>

<hr/>

**`Zap` is a JavaScript package manager _(think npm/pnpm/yarn)_ that aims to be faster than most of the existing ones.**

### Disclaimer

Zap is a **hobby** project that I am currently working on in my free time. Documentation is sparse, Windows support is partial at best and the code is not yet ready for production.

I am not looking for contributors at the moment, but feel free to open an issue if you have any question or suggestion.

#### ⚠️ TLDR: Use it at your own risk

## Installation

```bash
npm i -g @zap.org/zap
zap --help
```

## Features

#### Check the [project board](https://github.com/users/elbywan/projects/1/views/1) for the current status of the project.

Here is a non exhaustive list of features that are currently implemented:

- **Classic (npm-like) or isolated (pnpm-like) installs**

```bash
zap i --install-strategy isolated
```

```json
"zap": {
  "install_strategy": "isolated"
}
```

- **[Workspaces](https://docs.npmjs.com/cli/v9/using-npm/workspaces?v=true#defining-workspaces)**

```json
"workspaces": [
  "core/*",
  "packages/*"
],
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
  "packageExtensions": {
    "react-redux@1": {
      "peerDependencies": {
        "react-dom": "*"
      }
    }
  }
}
```

- **Aliases**

```bash
zap i my-react@npm:react
zap i jquery2@npm:jquery@2
zap i jquery3@npm:jquery@3
```

## Development

### Prerequisites

- [Install crystal](https://crystal-lang.org/install/)
- _(optional)_ Install the [vscode extension](https://marketplace.visualstudio.com/items?itemName=crystal-lang-tools.crystal-lang) and [crystalline](https://github.com/elbywan/crystalline)

### Setup

```
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

## Credits

- [pnpm](https://pnpm.io/)
- [bun](https://bun.sh/)
- [npm](https://www.npmjs.com/)
- [yarn](https://yarnpkg.com/)
