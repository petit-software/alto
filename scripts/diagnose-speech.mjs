// Developer-only, local synthesis comparison. Does not play or upload audio.
// node scripts/diagnose-speech.mjs /path/Alto.app /path/model-folder /new/output-folder
import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';

const [bundle, modelFolder, outputFolder] = process.argv.slice(2);
if (!outputFolder) throw new Error('Expected app bundle, installed model folder, and new output folder');
await fs.mkdir(outputFolder, { recursive: false, mode: 0o700 });
const manifest = JSON.parse(await fs.readFile(path.join(modelFolder, 'alto-model.json'), 'utf8'));
const model = manifest.model ?? manifest;
const weight = model.files.find(f => f.path.endsWith('.safetensors') && !f.path.startsWith('voices/'));
const voices = model.files.filter(f => f.path.startsWith('voices/') && f.path.endsWith('.safetensors')).slice(0, 4);
const worker = spawn(path.resolve(bundle, 'Contents/Helpers/AltoSpeechWorker'), [path.resolve(outputFolder)], { stdio: ['pipe', 'ignore', 'inherit'] });
const passages = [
  'Alto reads entirely on your Mac.',
  'Reading should feel calm and effortless, whether you are following a short note or a longer passage about the world around you, with every word spoken clearly and without distracting noise in the background.',
  'When the morning sun appeared over the hills, the village slowly came to life, and people opened their windows to welcome the fresh air, while a small group of friends gathered beside the river to plan their journey through the countryside, taking their time to enjoy the quiet streets and the sound of birds in the trees before they set off together toward the mountains in the distance.'
];
const results = [];
try {
  for (const voice of voices) for (const [index, text] of passages.entries()) {
    const output = path.resolve(outputFolder, path.basename(voice.path, '.safetensors') + '-' + index + '.wav');
    worker.stdin.write(JSON.stringify({ model: path.resolve(modelFolder, weight.path), voice: path.resolve(modelFolder, voice.path), text, output }) + '\n');
    let response;
    const deadline = Date.now() + 120000;
    while (Date.now() < deadline) {
      try { response = JSON.parse(await fs.readFile(output + '.json', 'utf8')); break; }
      catch (e) { if (e.code !== 'ENOENT') throw e; }
      if (worker.exitCode !== null) throw new Error('Worker exited: ' + worker.exitCode);
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    if (!response || response.error) throw new Error(response?.error ?? 'Worker timed out');
    const data = await fs.readFile(output);
    let pcm, sampleRate;
    for (let pos = 12; pos + 8 <= data.length;) {
      const name = data.toString('ascii', pos, pos + 4), length = data.readUInt32LE(pos + 4);
      if (name === 'fmt ') {
        if (data.readUInt16LE(pos + 8) !== 3 || data.readUInt16LE(pos + 22) !== 32) throw new Error('Expected float32 WAV');
        sampleRate = data.readUInt32LE(pos + 12);
      }
      if (name === 'data') pcm = data.subarray(pos + 8, pos + 8 + length);
      pos += 8 + length + (length % 2);
    }
    let peak = 0, square = 0, clipped = 0, leadingSquare = 0, leadingCount = 0;
    const blocks = [];
    for (let start = 0; start < pcm.length / 4; start += 1200) {
      let blockSquare = 0, crossings = 0, previous = 0, count = 0;
      for (let i = start; i < Math.min(start + 1200, pcm.length / 4); i++) {
        const value = pcm.readFloatLE(i * 4);
        if (!Number.isFinite(value)) throw new Error('Non-finite sample');
        peak = Math.max(peak, Math.abs(value)); square += value * value;
        clipped += Math.abs(value) >= 1 ? 1 : 0;
        if (i < sampleRate * 0.2) { leadingSquare += value * value; leadingCount++; }
        blockSquare += value * value; crossings += value * previous < 0 ? 1 : 0; previous = value; count++;
      }
      blocks.push({ seconds: start / sampleRate, rms: Math.sqrt(blockSquare / count), zeroCrossingRate: crossings / count });
    }
    const result = { voice: voice.path, characters: text.length, output, seconds: response.samples / sampleRate,
      generationSeconds: response.seconds, peak, rms: Math.sqrt(square / (pcm.length / 4)), clipped,
      leadingRMS: Math.sqrt(leadingSquare / leadingCount), blocks };
    results.push(result);
    console.log(JSON.stringify({ ...result, blocks: undefined }));
  }
  await fs.writeFile(path.join(outputFolder, 'measurements.json'), JSON.stringify(results, null, 2));
} finally { worker.stdin.end(); worker.kill(); }
