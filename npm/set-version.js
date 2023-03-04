const fs = require("fs");
const path = require("path");

const newVersion = process.argv[2];

console.log(`Bumping packages to version ${newVersion}...`);

const packages = [
  "darwin-arm64",
  "darwin-x64",
  "linux-x64",
  "win32-x64",
  "zap",
];

packages.forEach((package) => {
  const pkgFilePath = path.resolve(__dirname, package, "package.json");
  const pkgJson = require(pkgFilePath);
  pkgJson.version = newVersion;

  if (package === "zap") {
    Object.getOwnPropertyNames(pkgJson.optionalDependencies).forEach(
      (dependency) => {
        pkgJson.optionalDependencies[dependency] = newVersion;
      }
    );
  }

  fs.writeFileSync(pkgFilePath, JSON.stringify(pkgJson, null, 2));
});
