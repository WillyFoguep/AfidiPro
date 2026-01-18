const fs = require("fs");
const path = require("path");

const capacitorBuildGradle = path.join(
  __dirname,
  "../node_modules/@capacitor/android/capacitor/build.gradle",
);

if (fs.existsSync(capacitorBuildGradle)) {
  let content = fs.readFileSync(capacitorBuildGradle, "utf8");

  if (content.includes("proguard-android.txt")) {
    content = content.replace(
      /getDefaultProguardFile\('proguard-android\.txt'\)/g,
      "getDefaultProguardFile('proguard-android-optimize.txt')",
    );

    fs.writeFileSync(capacitorBuildGradle, content);
    console.log("✓ Fixed ProGuard configuration in Capacitor");
  }
}
