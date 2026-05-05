import fs from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);

const palette = {
  black: "#0D0D0D",
  green: "#6DBE45",
  neutral300: "#C8D1CB",
  neutral100: "#E7ECE8",
  neutral200: "#D8DFDA",
};

const iosBrandingDir = path.join(rootDir, "apps/ios/branding");
const iosAssetsDir = path.join(rootDir, "apps/ios/TuneAV/App/Assets.xcassets");
const macAssetsDir = path.join(rootDir, "apps/macos/TuneAVMac/Assets.xcassets");

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

async function processedImageDataUrl(filePath, transform) {
  const input = sharp(filePath);
  const output = transform ? transform(input) : input;
  const data = await output.png().toBuffer();
  return `data:image/png;base64,${data.toString("base64")}`;
}

async function wordmarkSvg({ dark = false } = {}) {
  const icon = dark
    ? await processedImageDataUrl(
        path.join(iosAssetsDir, "BrandMark.imageset/brandmark.png"),
        (image) => image.modulate({ brightness: 0.84, saturation: 0.9 })
      )
    : await imageDataUrl(path.join(iosAssetsDir, "BrandMark.imageset/brandmark.png"));
  const tuneFill = dark ? palette.neutral200 : palette.black;
  return svgDocument(920, 300, `  <rect width="920" height="300" fill="transparent"/>
  <image x="28" y="40" width="220" height="220" href="${icon}"/>
  <line x1="290" y1="58" x2="290" y2="242" stroke="${palette.neutral300}" stroke-width="3"/>
  <text x="348" y="194" fill="${tuneFill}" font-family="Sora, Manrope, Arial, sans-serif" font-size="116" font-weight="800" letter-spacing="0">Tune</text>
  <g transform="translate(680 119) scale(0.743)" fill="none" stroke="${palette.green}" stroke-width="21" stroke-linecap="round" stroke-linejoin="round" aria-label="AV">
    <path d="M0 88 L52 0 L104 88"/>
    <path d="M108 0 L160 88 L212 0"/>
  </g>
`, dark ? "Tune AV wordmark dark" : "Tune AV wordmark");
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

async function writeSourceSvgs(wordmark, darkWordmark) {
  await fs.mkdir(iosBrandingDir, { recursive: true });
  await fs.writeFile(path.join(iosBrandingDir, "tune-av-wordmark.svg"), wordmark, "utf8");
  await fs.writeFile(path.join(iosBrandingDir, "tune-av-wordmark-dark.svg"), darkWordmark, "utf8");
}

async function removeLegacyBrandingAssets() {
  await Promise.all([
    fs.rm(path.join(iosBrandingDir, "tuneav-wordmark.svg"), { force: true }),
    fs.rm(path.join(iosBrandingDir, "tuneav-wordmark-dark.svg"), { force: true }),
  ]);
}

async function writeWordmarkAssets(wordmark, darkWordmark) {
  await renderPng(wordmark, path.join(iosAssetsDir, "OnboardingWordmark.imageset/tune-av-logo.png"), 920, 300);
  await renderPng(darkWordmark, path.join(iosAssetsDir, "OnboardingWordmark.imageset/tune-av-logo-dark.png"), 920, 300);
  await renderPng(wordmark, path.join(macAssetsDir, "OnboardingWordmark.imageset/tune-av-logo.png"), 920, 300);
}

const wordmark = await wordmarkSvg();
const darkWordmark = await wordmarkSvg({ dark: true });
await removeLegacyBrandingAssets();
await writeSourceSvgs(wordmark, darkWordmark);
await writeWordmarkAssets(wordmark, darkWordmark);

console.log(JSON.stringify({
  preserved: [
    "AppIcon",
    "BrandMark",
    "OnboardingHero",
  ],
  rebranded: "OnboardingWordmark",
}, null, 2));
