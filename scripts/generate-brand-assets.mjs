import fs from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);

const palette = {
  black: "#0D0D0D",
  green: "#6DBE45",
  neutral300: "#C8D1CB",
};

const iosBrandingDir = path.join(rootDir, "apps/ios/branding");
const iosAssetsDir = path.join(rootDir, "apps/ios/Avtunesys/App/Assets.xcassets");
const macAssetsDir = path.join(rootDir, "apps/macos/AvtunesysMac/Assets.xcassets");

function svgDocument(width, height, content, label) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-label="${label}">
  ${content}
</svg>
`;
}

async function imageDataUrl(filePath) {
  const data = await fs.readFile(filePath);
  return `data:image/png;base64,${data.toString("base64")}`;
}

async function wordmarkSvg() {
  const icon = await imageDataUrl(path.join(iosAssetsDir, "BrandMark.imageset/brandmark.png"));
  return svgDocument(1400, 300, `
  <rect width="1400" height="300" fill="transparent"/>
  <image x="24" y="34" width="232" height="232" href="${icon}"/>
  <line x1="322" y1="58" x2="322" y2="242" stroke="${palette.neutral300}" stroke-width="3"/>
  <text x="394" y="198" fill="${palette.green}" font-family="Sora, Manrope, Arial, sans-serif" font-size="116" font-weight="800" letter-spacing="0">AV</text>
  <text x="568" y="198" fill="${palette.black}" font-family="Sora, Manrope, Arial, sans-serif" font-size="116" font-weight="800" letter-spacing="0">Tune</text>
  <text x="850" y="198" fill="${palette.green}" font-family="Sora, Manrope, Arial, sans-serif" font-size="116" font-weight="800" letter-spacing="0">sys</text>
`, "AV Tunesys wordmark");
}

async function renderPng(svg, outputPath, width, height) {
  await sharp(Buffer.from(svg))
    .resize({
      width,
      height,
      fit: "contain",
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toFile(outputPath);
}

async function writeSourceSvgs(wordmark) {
  await fs.mkdir(iosBrandingDir, { recursive: true });
  await fs.writeFile(path.join(iosBrandingDir, "avtunesys-wordmark.svg"), wordmark, "utf8");
}

async function writeWordmarkAssets(wordmark) {
  await renderPng(wordmark, path.join(iosAssetsDir, "OnboardingWordmark.imageset/av-tunesys-logo.png"), 1400, 300);
  await renderPng(wordmark, path.join(macAssetsDir, "OnboardingWordmark.imageset/av-tunesys-logo.png"), 1400, 300);
}

const wordmark = await wordmarkSvg();
await writeSourceSvgs(wordmark);
await writeWordmarkAssets(wordmark);

console.log(JSON.stringify({
  preserved: [
    "AppIcon",
    "BrandMark",
    "LaunchBrand",
    "OnboardingHero",
  ],
  rebranded: "OnboardingWordmark",
}, null, 2));
