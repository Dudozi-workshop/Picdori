# 픽도리 · Picdori

사진의 크기·비율·용량을 맞추고 JPG와 PNG로 변환하는 두도지공방의 Flutter 앱입니다. Android와 iOS를 지원합니다.

## 기능

- 픽셀 지정, 비율 조정, 자르기 및 전체 사진 유지
- 목표 용량 설정, JPG·PNG 변환, 결과 파일 규격 확인
- 성공한 변환 결과 자동 보관, 기존 파일을 보존하는 재편집, 최근 삭제 항목 7일 복구

## 빌드 및 검증

저장소 루트에서 Flutter 플랫폼 프로젝트를 생성한 뒤 플랫폼 설정과 런처 아이콘을 적용합니다.

```sh
flutter create . --project-name picdori --org com.dudozi --platforms android,ios
rm -f test/widget_test.dart
python3 scripts/configure_android.py
python3 scripts/configure_ios.py
flutter pub get
dart run flutter_launcher_icons
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
```

iOS 시뮬레이터 빌드는 macOS와 Xcode 환경에서 `flutter build ios --simulator --debug`로 실행합니다. GitHub Actions의 `Picdori Flutter checks`에서 검수용 Android APK를 받을 수 있습니다.
