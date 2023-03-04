const fs = require("fs");
const path = require("path");

// This script replaces the bin/zap placeholder with the actual zap binary from the @zap.org package.

const packageName = `@zap.org/${process.platform}-${process.arch}`;
const modulePath = require.resolve(packageName + "/package.json");

if (!modulePath) {
  console.error(
    "Error: Could not locate ${packageName}.\n" +
      "\n" +
      "Either your current architecture (${process.platform}-${process.arch}) is not supported, or the package is not installed.\n" +
      "Make sure that your package manager is not ignoring optional dependencies.\n"
  );
  process.exit(1);
}

const originalPath = path.join(path.dirname(modulePath), "bin", "zap");
const targetPath = path.join(__dirname, "bin", "zap");
const intermediatePath = path.join(__dirname, "bin", "zap.bin");

try {
  fs.chmodSync(originalPath, 0o755);
  fs.linkSync(originalPath, intermediatePath);
  fs.renameSync(intermediatePath, targetPath);
} catch (error) {
  console.error("Error while installing the zap binary!");
  console.error(error);
  process.exit(2);
}
