"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.deactivate = exports.activate = void 0;
const vscode = __importStar(require("vscode"));
const child_process_1 = require("child_process");
const simplifierScript = `
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
            candidate = re.sub(r'simplify:\\s*', '', candidate).strip()
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
`;
function logToOutput(message) {
    const outputChannel = vscode.window.createOutputChannel('QSOL Simplify');
    outputChannel.appendLine(message);
    outputChannel.show(true);
}
function activate(context) {
    const simplifyCommand = vscode.commands.registerCommand('qsol-simplify.simplifyText', async () => {
        const editor = vscode.window.activeTextEditor;
        if (!editor)
            return vscode.window.showErrorMessage('No active editor found.');
        const selection = editor.selection;
        const selectedText = editor.document.getText(selection).trim();
        if (!selectedText)
            return vscode.window.showWarningMessage('Please select text to simplify.');
        const config = vscode.workspace.getConfiguration('qsol-simplify');
        const numPaths = config.get('numPaths', 3);
        const targetScore = config.get('targetScore', 80);
        try {
            const pythonPath = vscode.workspace.getConfiguration('python').get('pythonPath') || 'python3';
            const pythonProcess = (0, child_process_1.spawn)(pythonPath, ['-c', simplifierScript]);
            let stdout = '';
            let stderr = '';
            pythonProcess.stdout.on('data', (data) => { stdout += data.toString(); });
            pythonProcess.stderr.on('data', (data) => { stderr += data.toString(); });
            pythonProcess.stdin.write(JSON.stringify({ text: selectedText, num_paths: numPaths, target_score: targetScore }));
            pythonProcess.stdin.end();
            await new Promise((resolve, reject) => {
                pythonProcess.on('close', (code) => {
                    if (code !== 0)
                        reject(new Error(`Python exited with code ${code}: ${stderr}`));
                    else
                        resolve(null);
                });
            });
            if (stderr) {
                vscode.window.showErrorMessage('Simplification failed: ' + stderr);
                logToOutput('Error: ' + stderr);
                return;
            }
            const result = JSON.parse(stdout.trim());
            if (result && result.simplified) {
                editor.edit(editBuilder => { editBuilder.replace(selection, result.simplified); });
                vscode.window.showInformationMessage(`Simplified! Score: ${result.score.toFixed(2)} | Paths: ${result.paths_explored}`);
            }
            else {
                vscode.window.showWarningMessage('No result.');
                logToOutput('No result.');
            }
        }
        catch (error) {
            vscode.window.showErrorMessage('Failed: ' + error.message);
            logToOutput('Error: ' + error.message);
        }
    });
    const statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBar.text = `QSOL Simplify`;
    statusBar.tooltip = 'Adjust settings';
    statusBar.command = 'qsol-simplify.showSettings';
    statusBar.show();
    const showSettings = vscode.commands.registerCommand('qsol-simplify.showSettings', async () => {
        const config = vscode.workspace.getConfiguration('qsol-simplify');
        const pathsPick = await vscode.window.showInputBox({ prompt: 'num_paths (default 3)', value: config.get('numPaths', 3).toString() });
        const scorePick = await vscode.window.showInputBox({ prompt: 'target_score (default 80)', value: config.get('targetScore', 80).toString() });
        if (pathsPick)
            await config.update('numPaths', parseInt(pathsPick, 10), vscode.ConfigurationTarget.Global);
        if (scorePick)
            await config.update('targetScore', parseFloat(scorePick), vscode.ConfigurationTarget.Global);
    });
    context.subscriptions.push(simplifyCommand, showSettings, statusBar);
}
exports.activate = activate;
function deactivate() { }
exports.deactivate = deactivate;
