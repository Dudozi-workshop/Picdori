"""Remove the Flutter template debug key from a release candidate."""
from pathlib import Path

gradle = Path(__file__).resolve().parents[1] / "android/app/build.gradle.kts"
source = gradle.read_text()
template = 'signingConfig = signingConfigs.getByName("debug")'
unsigned = 'signingConfig = null'

if source.count(template) == 1 and unsigned not in source:
    gradle.write_text(source.replace(template, unsigned))
elif source.count(unsigned) != 1 or template in source:
    raise SystemExit("Review the app's existing release signing configuration.")
