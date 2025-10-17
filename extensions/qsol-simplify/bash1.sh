#!/bin/bash

# Fix package.json: Remove Python deps (handle via pip), add @types/node for TS
cat << EOF > package.json
{
  "name": "qsol-simplify",
  "displayName": "QSOL AI Simplification Guide",
  "description": "Simplifies text with φ-gating and Flesch scoring.",
  "version": "0.0.1",
  "engines": { "vscode": "^1.60.0" },
  "categories": ["Other"],
  "activationEvents": ["onCommand:qsol-simplify.simplifyText"],
  "main": "./out/extension.js",
  "contributes": {
    "commands": [{ "command": "qsol-simplify.simplifyText", "title": "QSOL: Simplify Selected Text" }],
    "keybindings": [{ "command": "qsol-simplify.simplifyText", "key": "ctrl+alt+s", "mac": "cmd+alt+s", "when": "editorTextFocus" }],
    "configuration": {
      "properties": {
        "qsol-simplify.numPaths": { "type": "integer", "default": 3 },
        "qsol-simplify.targetScore": { "type": "number", "default": 80 }
      }
    }
  },
  "scripts": { "compile": "tsc -p ./" },
  "devDependencies": { "@types/vscode": "^1.60.0", "typescript": "^4.9.5", "@types/node": "^20.0.0" },
  "license": "MIT"
}
EOF

# Install Node devDeps (local, no sudo needed)
npm install

# Update src/extension.ts with type fixes (Buffer for data, void for Promise)
cat << EOF > src/extension.ts
import * as vscode from 'vscode';
import { spawn } from 'child_process';

const simplifierScript = \`
import sys, json, nltk
from nltk.tokenize import sent_tokenize, word_tokenize
import textstat
from transformers import T5ForConditionalGeneration, T5Tokenizer
import re, numpy as np

nltk.download('punkt', quiet=True)
PHI = (1 + np.sqrt(5)) / 2

class AISimplifier:
    def _flesch_score(self, text):
        if not text.strip(): return 0.0
        sentences = len(sent_tokenize(text))
        words = len(word_tokenize(text))
        syllables = textstat.syllable_count(text)
        if sentences == 0 or words == 0: return 0.0
        asl = words / sentences
        asw = syllables / words
        return 206.835 - 1.015 * asl - 84.6 * asw

    def _phi_spiral_gate(self, paths):
        if len(paths) <= 1: return paths[0] if paths else {}
        for i, path in enumerate(paths):
            path['decay_score'] = path.get('score', 1.0) * (PHI ** (-i))
        return max(paths, key=lambda p: p['decay_score'])

    def simplify(self, text, max_length=512, num_paths=3, target_score=80):
        score = self._flesch_score(text)
        if score >= target_score: return {'original': text, 'simplified': text, 'score': score, 'paths_explored': 0}
        paths = []
        tokenizer = T5Tokenizer.from_pretrained('t5-small')
        model = T5ForConditionalGeneration.from_pretrained('t5-small')
        base_prompt = f"simplify: {text}"
        inputs = tokenizer.encode(base_prompt, return_tensors='pt', max_length=max_length, truncation=True)
        for beam in range(1, num_paths + 1):
            outputs = model.generate(inputs, max_length=150, num_beams=beam, early_stopping=True, do_sample=True, temperature=0.7)
            candidate = tokenizer.decode(outputs[0], skip_special_tokens=True)
            candidate = re.sub(r'simplify:\\\s*', '', candidate).strip()
            if candidate and len(candidate) > 10:
                paths.append({'simplified': candidate, 'score': self._flesch_score(candidate)})
        if not paths: return {'original': text, 'simplified': text, 'score': score, 'paths_explored': 0}
        best = self._phi_spiral_gate(paths)
        return {'original': text, 'simplified': best['simplified'], 'score': best['score'], 'paths_explored': len(paths)}

if __name__ == '__main__':
    input_data = json.loads(sys.stdin.read().strip())
    simplifier = AISimplifier()
    result = simplifier.simplify(input_data['text'], num_paths=input_data.get('num_paths', 3), target_score=input_data.get('target_score', 80))
    print(json.dumps(result))
\`;

function logToOutput(message: string) {
    const outputChannel = vscode.window.createOutputChannel('QSOL Simplify');
    outputChannel.appendLine(message);
    outputChannel.show(true);
}

export function activate(context: vscode.ExtensionContext) {
    const simplifyCommand = vscode.commands.registerCommand('qsol-simplify.simplifyText', async () => {
        const editor = vscode.window.activeTextEditor;
        if (!editor) return vscode.window.showErrorMessage('No active editor found.');
        const selection = editor.selection;
        const selectedText = editor.document.getText(selection).trim();
        if (!selectedText) return vscode.window.showWarningMessage('Please select text to simplify.');
        const config = vscode.workspace.getConfiguration('qsol-simplify');
        const numPaths = config.get<number>('numPaths', 3);
        const targetScore = config.get<number>('targetScore', 80);
        try {
            const pythonPath = vscode.workspace.getConfiguration('python').get<string>('pythonPath') || 'python3';
            const pythonProcess = spawn(pythonPath, ['-c', simplifierScript]);
            let stdout = ''; let stderr = '';
            pythonProcess.stdout.on('data', (data: Buffer) => { stdout += data.toString(); });
            pythonProcess.stderr.on('data', (data: Buffer) => { stderr += data.toString(); });
            pythonProcess.stdin.write(JSON.stringify({ text: selectedText, num_paths: numPaths, target_score: targetScore }));
            pythonProcess.stdin.end();
            await new Promise<void>((resolve, reject) => {
                pythonProcess.on('close', (code: number) => {
                    if (code !== 0) reject(new Error(\`Python exited with code \${code}: \${stderr}\`));
                    else resolve();
                });
            });
            if (stderr) { vscode.window.showErrorMessage('Simplification failed: ' + stderr); logToOutput('Error: ' + stderr); return; }
            const result = JSON.parse(stdout.trim());
            if (result && result.simplified) {
                editor.edit(editBuilder => { editBuilder.replace(selection, result.simplified); });
                vscode.window.showInformationMessage(\`Simplified! Score: \${result.score.toFixed(2)} | Paths: \${result.paths_explored}\`);
            } else { vscode.window.showWarningMessage('No result.'); logToOutput('No result.'); }
        } catch (error: any) { vscode.window.showErrorMessage('Failed: ' + error.message); logToOutput('Error: ' + error.message); }
    });
    const statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBar.text = \`QSOL Simplify\`; statusBar.tooltip = 'Adjust settings'; statusBar.command = 'qsol-simplify.showSettings'; statusBar.show();
    const showSettings = vscode.commands.registerCommand('qsol-simplify.showSettings', async () => {
        const config = vscode.workspace.getConfiguration('qsol-simplify');
        const pathsPick = await vscode.window.showInputBox({ prompt: 'num_paths (default 3)', value: config.get('numPaths', 3).toString() });
        const scorePick = await vscode.window.showInputBox({ prompt: 'target_score (default 80)', value: config.get('targetScore', 80).toString() });
        if (pathsPick) await config.update('numPaths', parseInt(pathsPick, 10), vscode.ConfigurationTarget.Global);
        if (scorePick) await config.update('targetScore', parseFloat(scorePick), vscode.ConfigurationTarget.Global);
    });
    context.subscriptions.push(simplifyCommand, showSettings, statusBar);
}

export function deactivate() {}
EOF

# Install Python deps (use available torch 2.5.0+cpu; no sudo in conda env)
pip install textstat==0.7.3 transformers==4.35.0 numpy==1.24.3 nltk==3.8.1
pip install torch==2.5.0+cpu --index-url https://download.pytorch.org/whl/cpu

# Compile (fixes TS errors with types)
npm run compile

# Package (.vsix; ignore production deps warning—Python not Node)
vsce package --no-dependencies

# Commit/push from root (cd up if needed)
cd ../..
git add extensions/qsol-simplify
git commit -m "Fix TS types, deps, and compile for qsol-simplify"
git push origin master
