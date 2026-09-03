import { mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import sharp from "sharp";
import {
  prepareMinimalBodyFill,
  restoreMinimalBodyFillSubject,
} from "../lib/image.js";

const outputDirectory = fileURLToPath(new URL("../../build/fill-body-smoke/", import.meta.url));
await mkdir(outputDirectory, { recursive: true });

type Fixture = {
  name: string;
  width: number;
  height: number;
  subjectSVG: string;
  extensionSVG: (
    canvasWidth: number,
    canvasHeight: number,
    originalX: number,
    originalWidth: number,
    originalHeight: number,
  ) => string;
};

const fixtures: Fixture[] = [
  {
    name: "right-edge",
    width: 720,
    height: 900,
    subjectSVG: `
      <svg width="720" height="900" xmlns="http://www.w3.org/2000/svg">
        <ellipse cx="455" cy="190" rx="112" ry="145" fill="#d8a07b"/>
        <path d="M320 330 C390 295 520 295 610 340 L760 500 L760 820 L250 820 L260 470 Z" fill="#315b88"/>
      </svg>`,
    extensionSVG: (canvasWidth, canvasHeight, originalX, originalWidth) => `
      <svg width="${canvasWidth}" height="${canvasHeight}" xmlns="http://www.w3.org/2000/svg">
        <rect x="${originalX + originalWidth - 20}" y="440" width="${canvasWidth}" height="380" fill="#315b88"/>
      </svg>`,
  },
  {
    name: "left-right-bottom",
    width: 720,
    height: 900,
    subjectSVG: `
      <svg width="720" height="900" xmlns="http://www.w3.org/2000/svg">
        <ellipse cx="360" cy="185" rx="108" ry="142" fill="#b97858"/>
        <path d="M-35 500 C85 350 220 315 360 320 C510 315 655 355 755 505 L755 940 L-35 940 Z" fill="#7a3f5d"/>
      </svg>`,
    extensionSVG: (canvasWidth, canvasHeight, originalX, originalWidth, originalHeight) => `
      <svg width="${canvasWidth}" height="${canvasHeight}" xmlns="http://www.w3.org/2000/svg">
        <rect x="0" y="500" width="${originalX + 15}" height="${canvasHeight - 500}" fill="#7a3f5d"/>
        <rect x="${originalX + originalWidth - 15}" y="500" width="${canvasWidth}" height="${canvasHeight - 500}" fill="#7a3f5d"/>
        <rect x="0" y="${originalHeight - 15}" width="${canvasWidth}" height="${canvasHeight}" fill="#7a3f5d"/>
      </svg>`,
  },
];

for (const fixture of fixtures) {
  const source = await sharp({
    create: {
      width: fixture.width,
      height: fixture.height,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([{ input: Buffer.from(fixture.subjectSVG) }])
    .png()
    .toBuffer();
  const preparation = await prepareMinimalBodyFill(source, {
    face: { x: 0.34, y: 0.04, width: 0.3, height: 0.32 },
  });
  if (!preparation.shouldFill) throw new Error(`${fixture.name}: expected fill`);

  const generated = await sharp({
    create: {
      width: preparation.mapping.canvasWidth,
      height: preparation.mapping.canvasHeight,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([{
      input: Buffer.from(fixture.extensionSVG(
        preparation.mapping.canvasWidth,
        preparation.mapping.canvasHeight,
        preparation.mapping.originalX,
        preparation.mapping.originalWidth,
        preparation.mapping.originalHeight,
      )),
    }])
    .png()
    .toBuffer();
  const restored = await restoreMinimalBodyFillSubject(
    generated,
    preparation.personLayer,
    preparation.mapping,
  );

  await Promise.all([
    sharp(source)
      .flatten({ background: { r: 36, g: 38, b: 43 } })
      .png()
      .toFile(`${outputDirectory}/${fixture.name}-before.png`),
    sharp(preparation.mask)
      .png()
      .toFile(`${outputDirectory}/${fixture.name}-mask.png`),
    sharp(restored)
      .flatten({ background: { r: 36, g: 38, b: 43 } })
      .png()
      .toFile(`${outputDirectory}/${fixture.name}-after.png`),
  ]);
}

console.log(`fill-body visual fixtures: ${outputDirectory}`);
