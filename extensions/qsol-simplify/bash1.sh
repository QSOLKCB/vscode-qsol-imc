# Fix pip torch (2.1.0 unavailable; use stable CPU version—no RTX needed here, but add --index-url for CUDA if wanted later)
pip uninstall torch -y  # Clean if partial install
pip install torch==2.4.1 --index-url https://download.pytorch.org/whl/cpu

# Create tsconfig.json if missing (or overwrite to ensure)
cat << EOF > tsconfig.json
{
  "compilerOptions": {
    "target": "es2020",
    "module": "commonjs",
    "outDir": "./out",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true
  }
}
EOF

# Re-install Node devDeps (safe; ensures typescript)
npm install

# Compile (builds out/extension.js)
npm run compile

# Package (creates .vsix; answer 'y' to warnings—add "repository" to package.json later)
vsce package

# Back to repo root, commit/push (assumes changes staged; master branch)
cd ../..
git add extensions/qsol-simplify
git commit -m "Fix compile and deps for qsol-simplify extension"
git push origin master
