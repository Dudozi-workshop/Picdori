import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'core/image_processor.dart';
import 'core/size_presets.dart';
import 'services/output_saver.dart';
import 'services/photo_importer.dart';
import 'widgets/crop_editor.dart';
import 'ui/picdori_bento.dart';
import 'ui/library_pages.dart';
import 'ui/management_pages.dart';
import 'services/picdori_archive.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PicdoriApp());
}

class PicdoriApp extends StatelessWidget {
  const PicdoriApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '픽도리',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: PicdoriColors.background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: PicdoriColors.accent,
            surface: PicdoriColors.background,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: PicdoriColors.background,
            foregroundColor: PicdoriColors.ink,
            elevation: 0,
            centerTitle: false,
          ),
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: PicdoriColors.paper,
            surfaceTintColor: Colors.transparent,
            indicatorColor: PicdoriColors.peach,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: PicdoriColors.coral,
              foregroundColor: const Color(0xFF301F19),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: PicdoriColors.paper,
            isDense: true,
            border: OutlineInputBorder(
              borderSide: const BorderSide(color: PicdoriColors.outline),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        home: const EditorPage(),
      );
}

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    this.initialSource,
    this.initialWidth,
    this.initialHeight,
    this.initialResult,
    this.initialSaveFailure,
  });

  /// Optional photo fixture for widget testing; not used in production.
  final Uint8List? initialSource;
  final int? initialWidth;
  final int? initialHeight;
  /// Optional result fixture for UI tests. Never used by production startup.
  final ImageResult? initialResult;
  /// Allows a result recovery state to be rendered in widget tests.
  final String? initialSaveFailure;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _picker = ImagePicker();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _customKb = TextEditingController(text: '200');

  Uint8List? _source;
  Uint8List? _cropBytes;
  int? _originalWidth;
  int? _originalHeight;
  int? _originalFileBytes;
  String _originalFormat = 'JPG';
  bool _heicConverted = false;
  String _preset = 'original';
  String _ratioPreset = 'original';
  bool _saving = false;
  bool _keepRatio = true;
  double _lockedAspect = 1.0;
  int? _maxBytes;
  bool _customLimit = false;
  bool _busy = false;
  GeometryMode _geometry = GeometryMode.fit;
  OutputFormat _format = OutputFormat.jpg;
  ImageResult? _result;
  String? _resultPath;
  String? _saveFailure;
  String? _retrySaveAction;

  final PicdoriArchive _archive = PicdoriArchive();
  bool _archiveReady = false;
  Future<void>? _archiveInitialization;
  String? _archiveError;
  String? _archiveFailure;
  String? _archivedResultId;
  bool _archiveReused = false;
  String? _editingSourceId;
  PicdoriFile? _detailFile;
  String _screen = 'home';
  String _tool = 'all';
  String _allTab = 'size';
  String _sizeTab = 'ratio';

  @override
  void initState() {
    super.initState();
    _initializeArchive();
    final source = widget.initialSource;
    final width = widget.initialWidth;
    final height = widget.initialHeight;
    if (source != null && width != null && height != null &&
        width > 0 && height > 0) {
      _source = source;
      _originalWidth = width;
      _originalHeight = height;
      _width.text = '$width';
      _height.text = '$height';
      _lockedAspect = width / height;
      _screen = 'edit';
      if (widget.initialResult != null) {
        _result = widget.initialResult;
        _screen = 'result';
        if (widget.initialSaveFailure != null) {
          _saveFailure = widget.initialSaveFailure;
          _retrySaveAction = 'gallery';
        }
      }
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _recoverPickedPhoto();
    }
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _customKb.dispose();
    super.dispose();
  }

  Future<void> _initializeArchive() =>
      _archiveInitialization ??= _loadArchive().whenComplete(() {
        _archiveInitialization = null;
      });

  Future<void> _loadArchive() async {
    if (_archiveError != null) setState(() => _archiveError = null);
    try {
      await _archive.initialize();
      if (!mounted) return;
      setState(() { _archiveReady = true; _archiveError = null; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _archiveError = '내 파일을 열지 못했어요.'; });
    }
  }

  Future<void> _retryArchive() async {
    if (_busy || _saving) return;
    setState(() => _busy = true);
    try {
      await _archiveResult();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveResult() async {
    final output = _result;
    if (output == null) return;
    if (_archiveFailure != null) setState(() => _archiveFailure = null);
    try {
      if (!_archiveReady) await _initializeArchive();
      if (!mounted) return;
      if (!_archiveReady) throw StateError('보관함이 준비되지 않았어요.');
      final saved = await _archive.save(output,
        sourceId: _editingSourceId,
        settings: {
          'width': output.width, 'height': output.height,
          'format': output.extension.toUpperCase(),
          'mode': _geometry.name,
          'maxBytes': _selectedLimit,
        });
      if (!mounted) return;
      setState(() {
        _archivedResultId = saved.file.id;
        _archiveReused = saved.reused;
        _archiveFailure = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _archiveFailure = '내 파일에 보관하지 못했어요. 다시 시도해 주세요.';
      });
    }
  }

  Future<void> _openStored(PicdoriFile file, {bool reedit = false}) async {
    try {
      final bytes = await _archive.loadBytes(file);
      if (!mounted || _screen != 'detail' || _detailFile?.id != file.id) return;
      setState(() {
        _source = bytes;
        _originalWidth = file.width;
        _originalHeight = file.height;
        _originalFileBytes = file.size;
        _originalFormat = file.format;
        _heicConverted = false;
        _width.text = '${file.width}';
        _height.text = '${file.height}';
        _lockedAspect = file.width / file.height;
        _keepRatio = true;
        _preset = 'original';
        _ratioPreset = 'original';
        _geometry = GeometryMode.fit;
        _cropBytes = null;
        _maxBytes = null;
        _customLimit = false;
        _format = file.format == 'PNG' ? OutputFormat.png : OutputFormat.jpg;
        _tool = 'all';
        _allTab = 'size';
        _sizeTab = 'ratio';
        _editingSourceId = file.id;
        _clearResult();
        if (reedit) {
          _screen = 'edit';
        } else {
          _result = ImageResult(bytes: bytes, width: file.width,
            height: file.height, format: _format);
          _resultPath = file.path;
          _archivedResultId = file.id;
          _screen = 'storedExport';
        }
      });
    } catch (_) {
      _message('보관된 사진을 열지 못했어요.');
    }
  }

  Future<void> _reuseHistory(PicdoriHistory job) =>
      _pickPhoto(settings: job.settings);

  Future<bool> _moveToTrash(List<String> ids, {int hiddenCount = 0}) async {
    if (ids.isEmpty) return false;
    final ok = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text('사진 ${ids.length}개를 삭제할까요?'),
        content: Text(
          '최근 삭제한 항목으로 이동하고 7일간 복구할 수 있어요. '
          '저장 공간은 아직 확보되지 않아요.'
          '${hiddenCount == 0 ? '' : '\n\n현재 검색·필터 결과에 보이지 않는 파일 $hiddenCount개도 함께 이동해요.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('최근 삭제로 이동')),
        ]));
    if (ok != true || !mounted) return false;
    try {
      await _archive.moveToTrash(ids);
      if (!mounted) return true;
      setState(() {});
      _message('최근 삭제한 항목으로 이동했어요.');
      return true;
    } catch (_) {
      _message('삭제에 실패했어요. 다시 시도해 주세요.');
      return false;
    }
  }

  Future<void> _restoreTrash(List<String> ids) async {
    try {
      await _archive.restore(ids);
      if (!mounted) return;
      setState(() {});
      _message('내 파일로 복구했어요.');
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {});
      _message(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {});
      _message('복구하지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _purgeTrash(List<String> ids) async {
    if (ids.isEmpty) return;
    final yes = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${ids.length}개를 영구 삭제할까요?'),
        content: const Text('픽도리에서 복구할 수 없어요. 기기 사진첩 등에 따로 저장한 사본은 유지돼요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('영구 삭제')),
        ]));
    if (yes != true) return;
    try {
      await _archive.permanentlyDelete(ids);
      if (!mounted) return;
      setState(() {});
      _message('영구 삭제를 완료했어요.');
    } catch (_) {
      _message('일부 파일을 삭제하지 못했어요. 다시 확인해 주세요.');
      if (mounted) setState(() {});
    }
  }

  void _selectTab(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_busy || _saving) return;
    const tabs = ['home', 'files', 'history', 'settings'];
    setState(() { _screen = tabs[index]; _detailFile = null; });
  }

  void _clearResult() {
    _archivedResultId = null;
    _archiveReused = false;
    _archiveFailure = null;
    _result = null;
    _resultPath = null;
    _saveFailure = null;
    _retrySaveAction = null;
  }

  void _clearSaveFailure() {
    if (!mounted) return;
    setState(() {
      _saveFailure = null;
      _retrySaveAction = null;
    });
  }

  void _setSaveFailure(String message, String action) {
    if (!mounted) return;
    setState(() {
      _saveFailure = message;
      _retrySaveAction = action;
    });
  }

  void _retrySave() {
    switch (_retrySaveAction) {
      case 'gallery':
        _saveGallery();
      case 'file':
        _saveFile();
      case 'share':
        _share();
    }
  }

  Future<void> _openTool(String tool) async {
    if (_busy || _saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _editingSourceId = null;
      _tool = tool;
      _allTab = tool == 'compress' || tool == 'format' ? tool : 'size';
      _sizeTab = 'ratio';
      _screen = 'edit';

      // Every tool starts from the original image. Switching modes must
      // never silently carry over a crop, pixel size or conversion constraint.
      // Additional settings inside the editor retain the current job instead.
      if (_source != null && _originalWidth != null &&
          _originalHeight != null) {
        _width.text = '${_originalWidth!}';
        _height.text = '${_originalHeight!}';
        _lockedAspect = _originalWidth! / _originalHeight!;
        _keepRatio = true;
        _preset = 'original';
        _ratioPreset = 'original';
        _geometry = GeometryMode.fit;
        _cropBytes = null;
        _format = _initialFormat(_originalFormat);
        _clearResult();
      }
      _maxBytes = tool == 'compress' ? 500000 : null;
      _customLimit = false;
    });
    if (_source == null) await _pickPhoto(returnHomeOnCancel: true);
  }

  OutputFormat _initialFormat(String original) {
    if (_tool == 'format') {
      return original == 'JPG' ? OutputFormat.png : OutputFormat.jpg;
    }
    return original == 'PNG' ? OutputFormat.png : OutputFormat.jpg;
  }

  void _returnToEditor() => setState(() => _screen = 'edit');

  void _returnHome() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _screen = 'home');
  }

  String get _toolTitle => switch (_tool) {
    'size' => '사진 크기 맞추기',
    'compress' => '사진 용량 줄이기',
    'format' => '파일 형식 바꾸기',
    _ => '한 번에 맞추기',
  };

  String _byteLabel(int bytes) {
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
    return '${(bytes / 1000000).toStringAsFixed(2)} MB';
  }

  double get _previewRatio {
    final width = int.tryParse(_width.text);
    final height = int.tryParse(_height.text);
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    if (_originalWidth != null && _originalHeight != null &&
        _originalHeight! > 0) {
      return _originalWidth! / _originalHeight!;
    }
    return 1.0;
  }

  String? get _pixelError {
    final width = int.tryParse(_width.text);
    final height = int.tryParse(_height.text);
    if (width == null || height == null || width < 1 || height < 1) {
      return '가로·세로 픽셀은 1 이상의 숫자로 입력해 주세요.';
    }
    if (width > 10000 || height > 10000 || width * height > 20000000) {
      return '각 변 10000px 이하, 전체 2000만 픽셀까지 지원해요.';
    }
    return null;
  }

  int? get _selectedLimit {
    if (!_customLimit) return _maxBytes;
    final kb = int.tryParse(_customKb.text);
    return kb == null ? null : kb * 1000;
  }

  String _limitLabel(int bytes) => bytes % 1000000 == 0
      ? '${bytes ~/ 1000000} MB' : '${bytes ~/ 1000} KB';

  String? get _limitError {
    if (!_customLimit) return null;
    final kb = int.tryParse(_customKb.text);
    if (kb == null || kb < 2) {
      return '최대 용량은 2KB 이상의 숫자로 입력해 주세요.';
    }
    return null;
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _setLimit(int? bytes) => setState(() {
        _maxBytes = bytes;
        _customLimit = false;
        _clearResult();
      });

  // Size and aspect are independently selectable. The current aspect remains
  // selected when applying the long-side size cap, and vice versa.
  void _applyPreset(String preset) {
    final sourceW = _originalWidth;
    final sourceH = _originalHeight;
    if (sourceW == null || sourceH == null) return;
    final nextRatio = preset == 'original' ? 'original' : _ratioPreset;
    final ratio = nextRatio == 'custom'
        ? _previewRatio
        : SizePresets.aspectByPreset(nextRatio) ??
            SizePresets.originalAspect(sourceW, sourceH);
    final target = SizePresets.forAspect(
      sourceWidth: sourceW,
      sourceHeight: sourceH,
      ratio: ratio,
    );
    var w = target.width;
    var h = target.height;
    if (preset == 'long1200') {
      final capped = SizePresets.capLongEdge(TargetPixels(w, h), 1200);
      w = capped.width;
      h = capped.height;
    }
    setState(() {
      _preset = preset;
      _ratioPreset = nextRatio;
      _width.text = '$w';
      _height.text = '$h';
      _lockedAspect = w / h;
      _keepRatio = true;
      _cropBytes = null;
      _clearResult();
    });
  }

  void _applyRatio(String preset) {
    final sourceW = _originalWidth;
    final sourceH = _originalHeight;
    if (sourceW == null || sourceH == null) return;
    final ratio = SizePresets.aspectByPreset(preset) ??
        SizePresets.originalAspect(sourceW, sourceH);
    final target = SizePresets.forAspect(
      sourceWidth: sourceW,
      sourceHeight: sourceH,
      ratio: ratio,
    );
    var w = target.width;
    var h = target.height;
    if (_preset == 'long1200') {
      final capped = SizePresets.capLongEdge(TargetPixels(w, h), 1200);
      w = capped.width;
      h = capped.height;
    }
    setState(() {
      _ratioPreset = preset;
      _width.text = '$w';
      _height.text = '$h';
      _lockedAspect = w / h;
      _keepRatio = true;
      _cropBytes = null;
      _clearResult();
    });
  }

  void _editPixel({required bool widthChanged}) {
    final edited = int.tryParse(widthChanged ? _width.text : _height.text);
    setState(() {
      _preset = 'manual';
      _ratioPreset = 'custom';
      if (_keepRatio && edited != null && edited > 0) {
        if (widthChanged) {
          _height.text = '${math.max(1, (edited / _lockedAspect).round())}';
        } else {
          _width.text = '${math.max(1, (edited * _lockedAspect).round())}';
        }
      }
      _cropBytes = null;
      _clearResult();
    });
  }

  void _toggleRatioLock() {
    setState(() {
      _keepRatio = !_keepRatio;
      if (_keepRatio) {
        final width = int.tryParse(_width.text);
        final height = int.tryParse(_height.text);
        if (width != null && height != null && width > 0 && height > 0) {
          _lockedAspect = width / height;
        }
      }
    });
  }

  Future<void> _pickPhoto({
    Map<String, dynamic>? settings,
    bool returnHomeOnCancel = false,
  }) async {
    if (_busy || _saving) return;
    setState(() => _busy = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (!mounted) return;
      if (picked != null) {
        await _importPhoto(picked, settings: settings);
      } else if (returnHomeOnCancel) {
        _returnHome();
      }
    } on PhotoImportException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('사진을 불러오지 못했어요. 다시 선택해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recoverPickedPhoto() async {
    var restoring = false;
    try {
      final response = await _picker.retrieveLostData();
      if (!mounted || _busy || _screen != 'home' || response.isEmpty) return;
      final files = response.files;
      final photo = files == null || files.isEmpty ? response.file : files.first;
      if (photo == null) {
        _message('선택한 사진을 복구하지 못했어요. 다시 선택해 주세요.');
        return;
      }
      restoring = true;
      setState(() => _busy = true);
      await _importPhoto(photo);
    } on MissingPluginException {
      // The picker is unavailable in environments without native plugins.
    } on PhotoImportException catch (error) {
      _message(error.message);
    } catch (_) {
      if (mounted && _screen == 'home' && (!_busy || restoring)) {
        _message('선택한 사진을 복구하지 못했어요. 다시 선택해 주세요.');
      }
    } finally {
      if (restoring && mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importPhoto(XFile picked, {Map<String, dynamic>? settings}) async {
    final imported = await PhotoImporter.fromPicked(picked);
    if (!mounted) return;
    setState(() {
      _source = imported.bytes;
      _originalWidth = imported.width;
      _originalHeight = imported.height;
      _originalFileBytes = imported.originalFileBytes;
      _originalFormat = imported.originalFormat;
      _heicConverted = imported.preconverted;
      _editingSourceId = null;
      _width.text = '${imported.width}';
      _height.text = '${imported.height}';
      _preset = 'original';
      _ratioPreset = 'original';
      _maxBytes = _tool == 'compress' ? 500000 : null;
      _customLimit = false;
      _geometry = GeometryMode.fit;
      _cropBytes = null;
      _lockedAspect = imported.width / imported.height;
      _keepRatio = true;
      _format = _initialFormat(imported.originalFormat);
      _clearResult();
      if (settings != null) {
        _tool = 'all';
        _allTab = 'size';
        _sizeTab = 'ratio';
        final w = settings['width'];
        final h = settings['height'];
        if (w is int && h is int && w > 0 && h > 0) {
          _width.text = '$w';
          _height.text = '$h';
          _lockedAspect = w / h;
          _preset = 'manual';
          _ratioPreset = 'custom';
        }
        _geometry = settings['mode'] == 'crop'
            ? GeometryMode.crop : GeometryMode.fit;
        _format = settings['format'] == 'PNG'
            ? OutputFormat.png : OutputFormat.jpg;
        final maximum = settings['maxBytes'] as int?;
        _maxBytes = maximum;
        _customLimit = maximum != null &&
            !const {200000, 500000, 1000000}.contains(maximum);
        if (_customLimit) _customKb.text = '${maximum! ~/ 1000}';
      }
      _screen = 'edit';
    });
  }

  Future<void> _adjustCrop() async {
    if (_source == null) return;
    final w = int.tryParse(_width.text);
    final h = int.tryParse(_height.text);
    if (w == null || h == null || w <= 0 || h <= 0) {
      _message('먼저 올바른 가로·세로 픽셀을 입력해 주세요.');
      return;
    }
    final adjusted = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => CropEditor(image: _source!, aspectRatio: w / h),
      ),
    );
    if (adjusted == null || !mounted) return;
    setState(() {
      _cropBytes = adjusted;
      _clearResult();
    });
  }

  Future<void> _convert() async {
    if (_source == null || _busy || _saving) return;
    if (_pixelError != null) {
      _message(_pixelError!);
      return;
    }
    if (_limitError != null) {
      _message(_limitError!);
      return;
    }
    final w = int.parse(_width.text);
    final h = int.parse(_height.text);
    final limit = _selectedLimit;
    setState(() => _busy = true);
    try {
      final result = await compute(
        runImageProcessing,
        ImageJob(
          source: _geometry == GeometryMode.crop && _cropBytes != null
              ? _cropBytes! : _source!,
          width: w,
          height: h,
          mode: _geometry,
          format: _format,
          maximumBytes: limit,
        ),
      );
      final temp = await getTemporaryDirectory();
      final folder = Directory('${temp.path}/picdori_exports');
      if (!await folder.exists()) await folder.create(recursive: true);
      final file = File(
        '${folder.path}/picdori_${DateTime.now().millisecondsSinceEpoch}.${result.extension}',
      );
      await file.writeAsBytes(result.bytes, flush: true);
      if (!mounted) return;
      setState(() {
        _result = result;
        _resultPath = file.path;
        _screen = 'result';
      });
      await _archiveResult();
    } catch (e) {
      _message(e is ImageProcessingException
          ? e.message : '변환에 실패했어요. 조건을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final path = _resultPath;
    if (path == null || _saving || _busy) return;
    // Guard against opening multiple share sheets or saving and sharing
    // concurrently while the platform UI is still active.
    setState(() => _saving = true);
    _clearSaveFailure();
    try {
      final renderObject = context.findRenderObject();
      final box = renderObject is RenderBox ? renderObject : null;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        sharePositionOrigin: box == null ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ));
    } catch (_) {
      _setSaveFailure('공유 메뉴를 열지 못했어요. 다시 시도해 주세요.', 'share');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveGallery() async {
    final result = _result;
    if (result == null || _saving || _busy) return;
    setState(() => _saving = true);
    _clearSaveFailure();
    try {
      await OutputSaver.saveToGallery(result);
      _message('사진첩에 저장했어요.');
    } catch (_) {
      _setSaveFailure(
        '사진첩 저장에 실패했어요. 사진 접근 권한과 저장 공간을 확인한 뒤 다시 시도해 주세요.',
        'gallery',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveFile() async {
    final result = _result;
    if (result == null || _saving || _busy) return;
    setState(() => _saving = true);
    _clearSaveFailure();
    try {
      final location = await OutputSaver.saveAsFile(result);
      if (location != null) _message('파일로 저장했어요.');
    } catch (_) {
      _setSaveFailure(
        '파일 저장에 실패했어요. 다른 저장 위치를 선택해 다시 시도해 주세요.',
        'file',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(17),
    Color color = PicdoriColors.paper,
  }) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: PicdoriColors.outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );

  Widget _label(String text, {double size = 16}) => Text(
        text,
        style: TextStyle(
          color: PicdoriColors.ink,
          fontSize: size,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _choice(String label, bool selected, VoidCallback callback) =>
      ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_busy || _saving) ? null : (_) => callback(),
        selectedColor: PicdoriColors.peach,
        backgroundColor: PicdoriColors.background,
        side: BorderSide(
          color: selected ? PicdoriColors.accent : PicdoriColors.outline,
        ),
        labelStyle: const TextStyle(color: PicdoriColors.ink),
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      );

  Widget _photoPreview({bool resultMode = false}) {
    final source = _source;
    final result = _result;
    if (source == null) return const SizedBox.shrink();
    final previewBytes = resultMode && result != null
        ? result.bytes
        : _cropBytes ?? source;
    final previewFormat = resultMode ? result?.format ?? _format : _format;
    final fit = resultMode
        ? BoxFit.contain
        : _geometry == GeometryMode.crop
            ? BoxFit.cover
            : BoxFit.contain;
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: math.min(
            260, math.max(178, MediaQuery.sizeOf(context).height * .30)),
          padding: EdgeInsets.all(resultMode ? 7 : 13),
          decoration: BoxDecoration(
            color: resultMode ? Colors.white : PicdoriColors.oatmeal,
            border: resultMode ? Border.all(color: PicdoriColors.outline) : null,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: AspectRatio(
              key: const ValueKey('picdori-preview-canvas'),
              aspectRatio: resultMode && result != null
                  ? result.width / result.height : _previewRatio,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Colors.white),
                child: CustomPaint(
                  painter: previewFormat == OutputFormat.png
                      ? const _TransparencyGrid() : null,
                  child: Image.memory(
                    previewBytes,
                    fit: fit,
                    gaplessPlayback: true,
                    cacheWidth: 1024,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!resultMode) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '원본 ${_originalWidth} × ${_originalHeight}px · '
                  '${_byteLabel(_originalFileBytes ?? source.length)}'
                  '${_heicConverted ? ' · HEIC 변환됨' : ''}',
                  style: const TextStyle(
                    fontSize: 12, color: PicdoriColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: (_busy || _saving) ? null : _pickPhoto,
                child: const Text('사진 변경'),
              ),
            ],
          ),
        ],
        if (!resultMode && _geometry == GeometryMode.crop &&
            _tool == 'all' && _allTab != 'size')
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : _adjustCrop,
              icon: const Icon(Icons.crop, size: 18),
              label: Text(_cropBytes == null
                  ? '자르기 위치 조절' : '자르기 위치 다시 조절'),
            ),
          ),
      ],
    );
  }

  Widget _photoPicker() => _panel(
        child: Column(
          children: [
            const SizedBox(height: 14),
            Image.asset(
              'assets/home/${_tool == 'size' ? 'resize' : _tool}.webp',
              height: 70,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 14),
            _label('사진을 선택해 주세요', size: 19),
            const SizedBox(height: 7),
            const Text('사진을 고르면 필요한 설정만 보여드려요.',
                style: TextStyle(color: PicdoriColors.muted, fontSize: 13)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _pickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_busy ? '사진 불러오는 중' : '사진 선택하기'),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );

  Widget _sizeSettings() => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('사진 크기 설정'),
            const SizedBox(height: 5),
            const Text('원하는 규격을 선택해 주세요.',
                style: TextStyle(fontSize: 12,
                    color: PicdoriColors.muted)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                key: const ValueKey('picdori-size-mode'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'ratio', label: Text('비율 선택')),
                  ButtonSegment(value: 'pixels', label: Text('픽셀 직접 입력')),
                ],
                selected: {_sizeTab},
                onSelectionChanged: (v) =>
                    setState(() => _sizeTab = v.first),
              ),
            ),
            const SizedBox(height: 12),
            if (_sizeTab == 'ratio') ...[
              Wrap(
                spacing: 7, runSpacing: 2,
                children: [
                  _choice('원본', _ratioPreset == 'original',
                      () => _applyRatio('original')),
                  for (final preset in ['1:1', '4:3', '3:4', '16:9', '9:16'])
                    _choice(preset, _ratioPreset == preset,
                        () => _applyRatio(preset)),
                ],
              ),
              if (_ratioPreset == 'custom')
                TextButton(
                  onPressed: () => setState(() => _sizeTab = 'pixels'),
                  child: const Text('직접 입력한 픽셀 확인'),
                ),
            ] else ...[
              Row(children: [
                Expanded(child: TextField(
                  key: const ValueKey('picdori-width'),
                  controller: _width,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  decoration: const InputDecoration(labelText: '가로 px'),
                  onChanged: (_) => _editPixel(widthChanged: true),
                )),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 7),
                  child: Text('×', style:
                      TextStyle(color: PicdoriColors.muted)),
                ),
                Expanded(child: TextField(
                  key: const ValueKey('picdori-height'),
                  controller: _height,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  decoration: const InputDecoration(labelText: '세로 px'),
                  onChanged: (_) => _editPixel(widthChanged: false),
                )),
                IconButton(
                  tooltip: _keepRatio
                      ? '비율 고정 해제' : '가로·세로 비율 고정',
                  onPressed: _busy ? null : _toggleRatioLock,
                  icon: Icon(_keepRatio ? Icons.lock_outline
                      : Icons.lock_open),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 2, children: [
                _choice('원본 크기', _preset == 'original',
                    () => _applyPreset('original')),
                _choice('최대 1200px', _preset == 'long1200',
                    () => _applyPreset('long1200')),
              ]),
            ],
            if (_pixelError != null) ...[
              const SizedBox(height: 5),
              Text(_pixelError!, style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              )),
            ],
            const SizedBox(height: 15),
            const Divider(color: PicdoriColors.outline),
            const SizedBox(height: 8),
            _label('사진 맞춤', size: 15),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 2, children: [
              _choice('전체 유지', _geometry == GeometryMode.fit, () {
                setState(() {
                  _geometry = GeometryMode.fit;
                  _cropBytes = null;
                  _clearResult();
                });
              }),
              _choice('잘라서 채우기',
                  _geometry == GeometryMode.crop, () {
                setState(() {
                  _geometry = GeometryMode.crop;
                  _cropBytes = null;
                  _clearResult();
                });
              }),
            ]),
            const SizedBox(height: 6),
            Text(
              _geometry == GeometryMode.fit
                  ? '비율이 다르면 여백이 생겨요.'
                  : '선택한 비율로 중앙을 잘라요. 위치는 직접 조절할 수 있어요.',
              style: const TextStyle(
                  color: PicdoriColors.muted, fontSize: 12),
            ),
            if (_geometry == GeometryMode.crop) ...[
              const SizedBox(height: 9),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _adjustCrop,
                  icon: const Icon(Icons.crop),
                  label: Text(_cropBytes == null
                      ? '자르기 위치 조절' : '자르기 위치 다시 조절'),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _limitSettings() => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('목표 파일 용량'),
            const SizedBox(height: 6),
            const Text('선택한 용량 이하로 사진을 만들어요.',
                style: TextStyle(
                    fontSize: 12, color: PicdoriColors.muted)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 2, children: [
              _choice('제한 없음', !_customLimit && _maxBytes == null,
                  () => _setLimit(null)),
              _choice('200KB', !_customLimit && _maxBytes == 200000,
                  () => _setLimit(200000)),
              _choice('500KB', !_customLimit && _maxBytes == 500000,
                  () => _setLimit(500000)),
              _choice('1MB', !_customLimit && _maxBytes == 1000000,
                  () => _setLimit(1000000)),
              _choice('직접 입력', _customLimit, () => setState(() {
                _customLimit = true;
                _clearResult();
              })),
            ]),
            if (_customLimit) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('picdori-custom-kb'),
                controller: _customKb,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '최대 용량 (KB)',
                  helperText: '1MB = 1000KB · 최소 2KB',
                ),
                onChanged: (_) => setState(_clearResult),
              ),
            ],
            if (_limitError != null) ...[
              const SizedBox(height: 6),
              Text(_limitError!, style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              )),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PicdoriColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '사진 크기는 유지하고 파일 용량을 조절해요. '
                '요청한 용량이 불가능하면 안내해 드려요.',
                style: TextStyle(fontSize: 12,
                    color: PicdoriColors.muted),
              ),
            ),
          ],
        ),
      );

  Widget _formatSettings() => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('저장할 파일 형식'),
            const SizedBox(height: 5),
            const Text('필요한 형식을 선택해 주세요.',
                style: TextStyle(
                    fontSize: 12, color: PicdoriColors.muted)),
            const SizedBox(height: 12),
            Row(children: [
              for (final format in OutputFormat.values) ...[
                if (format == OutputFormat.png) const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    color: _format == format
                        ? PicdoriColors.lavender
                        : PicdoriColors.background,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('picdori-format-${format.name}'),
                      onTap: (_busy || _saving) ? null : () => setState(() {
                        _format = format;
                        _clearResult();
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 20),
                        child: Column(children: [
                          const Icon(Icons.image_outlined,
                              size: 34, color: PicdoriColors.ink),
                          const SizedBox(height: 8),
                          Text(format == OutputFormat.jpg ? 'JPG' : 'PNG',
                              style: const TextStyle(
                                fontSize: 17,
                                color: PicdoriColors.ink,
                                fontWeight: FontWeight.w700,
                              )),
                          const SizedBox(height: 5),
                          Text(
                            format == OutputFormat.jpg
                                ? '일반 사진에 적합' : '투명 배경 지원',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: PicdoriColors.muted, fontSize: 11),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 12),
            const Text('사진의 가로·세로 픽셀은 그대로 유지해요.',
                style: TextStyle(fontSize: 12,
                    color: PicdoriColors.muted)),
          ],
        ),
      );

  Widget _activeSettings() {
    final active = _tool == 'all' ? _allTab : _tool;
    return switch (active) {
      'size' => _sizeSettings(),
      'compress' => _limitSettings(),
      'format' => _formatSettings(),
      _ => _sizeSettings(),
    };
  }

  Widget _outputSummary() {
    final pixels = _pixelError == null
        ? '${int.parse(_width.text)} × ${int.parse(_height.text)}px'
        : '크기 확인 필요';
    final maxBytes = _selectedLimit;
    final limit = _limitError != null
        ? '용량 확인 필요'
        : maxBytes == null ? '용량 제한 없음' : '${_limitLabel(maxBytes)} 이하';
    return _panel(
      color: PicdoriColors.peach,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _label('출력 규격', size: 12),
          Text(
            '$pixels · ${_format.name.toUpperCase()} · $limit',
            key: const ValueKey('picdori-output-summary'),
            style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: PicdoriColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _editorBody() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_source == null)
            _photoPicker()
          else ...[
            _photoPreview(),
            const SizedBox(height: 8),
            _outputSummary(),
            const SizedBox(height: 12),
            if (_tool == 'all') ...[
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  key: const ValueKey('picdori-all-tabs'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'size', label: Text('크기·비율')),
                    ButtonSegment(value: 'compress', label: Text('용량')),
                    ButtonSegment(value: 'format', label: Text('형식')),
                  ],
                  selected: {_allTab},
                  onSelectionChanged: (selection) =>
                      setState(() => _allTab = selection.first),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _activeSettings(),
            if (_tool != 'all') ...[
              const SizedBox(height: 10),
              TextButton.icon(
                key: const ValueKey('picdori-more-settings'),
                onPressed: () => setState(() {
                  _allTab = _tool;
                  _tool = 'all';
                }),
                icon: const Icon(Icons.tune, size: 20),
                label: const Text('다른 조건도 함께 설정하기'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _resultInfo(String title, String pixels, String bytes,
      {bool highlighted = false}) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: highlighted ? PicdoriColors.peach
                : PicdoriColors.background,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                color: PicdoriColors.muted, fontSize: 12)),
              const SizedBox(height: 8),
              Text(pixels,
                  style: const TextStyle(
                    color: PicdoriColors.ink, fontSize: 14,
                    fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(bytes, style: const TextStyle(
                color: PicdoriColors.muted, fontSize: 12)),
            ],
          ),
      );

  String _resultChange(ImageResult result, int originalBytes) {
    final size = '${_byteLabel(originalBytes)} → ${_byteLabel(result.size)}';
    final pixels = '${_originalWidth} × ${_originalHeight} → ${result.width} × ${result.height}px';
    final format = result.extension.toUpperCase();
    if (_tool == 'compress') return size;
    if (_tool == 'format' && _originalFormat != format) return '$_originalFormat → $format';
    if (_originalWidth != result.width || _originalHeight != result.height) return pixels;
    if (_originalFormat != format) return '$_originalFormat → $format';
    return size;
  }

  Widget _resultBody() {
    final result = _result;
    final source = _source;
    if (result == null || source == null) {
      return const Center(child: Text('결과가 없습니다.'));
    }
    final originalBytes = _originalFileBytes ?? source.length;
    final byteDifference = result.size - originalBytes;
    final percent = originalBytes > 0
        ? (byteDifference.abs() * 100 / originalBytes).round() : 0;
    final change = byteDifference == 0
        ? '용량 변화 없음'
        : '용량 ${percent == 0 ? '1% 미만' : '$percent%'} '
            '${byteDifference < 0 ? '감소' : '증가'}';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _photoPreview(resultMode: true),
          const SizedBox(height: 12),
          if (_screen == 'storedExport') ...[
            _label(_detailFile!.name, size: 18),
            const SizedBox(height: 4),
            Text('${result.width} × ${result.height}px · ${_byteLabel(result.size)} · ${result.extension.toUpperCase()}'),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 25,
                    color: Color(0xFF57876D)),
                const SizedBox(width: 9),
                Expanded(child: _label('사진이 완성됐어요', size: 19)),
              ],
            ),
            const SizedBox(height: 12),
            _panel(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(_resultChange(result, originalBytes), size: 17),
                const SizedBox(height: 9),
                LayoutBuilder(builder: (context, constraints) {
                  final original = _resultInfo(
                      '원본', '${_originalWidth} × ${_originalHeight}px',
                      '${_byteLabel(originalBytes)} · $_originalFormat');
                  final output = _resultInfo(
                      '완성', '${result.width} × ${result.height}px',
                      '${_byteLabel(result.size)} · '
                      '${result.extension.toUpperCase()}',
                      highlighted: true);
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  if (constraints.maxWidth < 235 || scale >= 1.4) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [original, const SizedBox(height: 8), output],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: original),
                      const SizedBox(width: 9),
                      Expanded(child: output),
                    ],
                  );
                }),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.verified_outlined,
                      color: Color(0xFF57876D), size: 19),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    '규격 검증 완료 · $change',
                    style: const TextStyle(color: PicdoriColors.muted,
                        fontSize: 12),
                  )),
                ]),
              ],
            )),
            const SizedBox(height: 10),
            _panel(
              color: _archivedResultId != null
                  ? PicdoriColors.sage : PicdoriColors.paper,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
              Icon(_archivedResultId != null ? Icons.folder_special_outlined
                : Icons.info_outline, size: 21,
                color: _archivedResultId != null
                  ? const Color(0xFF57876D) : PicdoriColors.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _archivedResultId != null
                        ? (_archiveReused
                            ? '같은 결과가 이미 보관돼 있어요.'
                            : '내 파일에 자동 보관됐어요.')
                        : (_archiveFailure ?? (_archiveReady
                            ? '내 파일에 보관하고 있어요.' : '보관함 준비 중이에요.')),
                    style: const TextStyle(fontSize: 12, color: PicdoriColors.ink),
                  ),
                ),
              ),
              if (_archiveFailure != null)
                TextButton(
                  onPressed: (_busy || _saving) ? null : _retryArchive,
                  child: const Text('재시도'),
                ),
            ])),
          ],
          const SizedBox(height: 12),
          if (_saveFailure != null) ...[
            Container(
              key: const ValueKey('picdori-save-failure'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PicdoriColors.oatmeal,
                border: Border.all(color: PicdoriColors.outline),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.info_outline, color: PicdoriColors.accent),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('저장 작업을 완료하지 못했어요',
                          style: TextStyle(
                              color: PicdoriColors.ink,
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 7),
                  Text(_saveFailure!, style: const TextStyle(
                      color: PicdoriColors.muted, fontSize: 13)),
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    key: const ValueKey('picdori-retry-save'),
                    onPressed: (_saving || _busy) ? null : _retrySave,
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 시도'),
                  ),
                ],
              ),
            ),
          ],
          if (_screen != 'storedExport') ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: (_busy || _saving) ? null : _returnToEditor,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('설정 다시 하기'),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 2,
              children: [
                TextButton.icon(
                  key: const ValueKey('picdori-new-photo'),
                  onPressed: (_saving || _busy) ? null : _pickPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text('다른 사진 선택'),
                ),
                TextButton(
                  onPressed: (_saving || _busy) ? null : _returnHome,
                  child: const Text('다른 작업 선택하기'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailBody() {
    final file = _detailFile;
    if (file == null) return const Center(child: Text('파일을 찾을 수 없어요.'));
    return ListView(padding: const EdgeInsets.all(18), children: [
      ClipRRect(borderRadius: BorderRadius.circular(18),
        child: Image.file(File(file.path), height: 260,
          fit: BoxFit.contain,
          errorBuilder: (ctx, e, stack) => const SizedBox(
            height: 260, child: Center(child: Icon(Icons.broken_image_outlined))))),
      const SizedBox(height: 15),
      Text(file.name, style: const TextStyle(fontSize: 17,
        fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('${file.width} × ${file.height}px · ${_byteLabel(file.size)} · ${file.format}',
        style: const TextStyle(color: PicdoriColors.muted)),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: () => _openStored(file, reedit: true),
        icon: const Icon(Icons.tune), label: const Text('다시 편집')),
      const Center(child: Text('기존 파일은 그대로 보관돼요.',
        style: TextStyle(fontSize: 12, color: PicdoriColors.muted))),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: () => _openStored(file),
        icon: const Icon(Icons.save_alt), label: const Text('저장·공유하기')),
      TextButton.icon(
        onPressed: () async {
          await _moveToTrash([file.id]);
          if (!mounted) return;
          if (_archive.find(file.id)?.inTrash == true) _selectTab(1);
        },
        icon: const Icon(Icons.delete_outline),
        label: const Text('최근 삭제로 이동')),
    ]);
  }

  Widget _archiveScreen() {
    if (_screen != 'settings' && !_archiveReady) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_archiveError ?? '내 파일을 불러오는 중이에요.'),
          const SizedBox(height: 12),
          if (_archiveError == null) const CircularProgressIndicator()
          else TextButton(onPressed: _initializeArchive,
            child: const Text('다시 시도')),
        ]));
    }
    return switch (_screen) {
      'files' => PicdoriLibraryView(
        archive: _archive, onOpen: (f) => setState(() {
          _detailFile = f; _screen = 'detail';
        }), onTrash: _moveToTrash),
      'history' => PicdoriHistoryView(
        archive: _archive, onReuse: _reuseHistory,
        onRemove: (h) async {
          try { await _archive.deleteHistory(h.id); if (mounted) setState(() {}); }
          catch (_) { _message('기록을 삭제하지 못했어요.'); }
        }),
      'settings' => PicdoriSettingsView(
        onStorage: () => setState(() => _screen = 'storage'),
        onTrash: () => setState(() => _screen = 'trash')),
      'trash' => PicdoriTrashView(archive: _archive,
        onRestore: _restoreTrash, onPurge: _purgeTrash),
      'storage' => PicdoriStorageView(archive: _archive,
        onTrash: () => setState(() => _screen = 'trash')),
      'detail' => _detailBody(),
      _ => const SizedBox.shrink(),
    };
  }

  String get _makeLabel {
    if (_busy) return '사진 만드는 중';
    if (_tool == 'format') return '${_format.name.toUpperCase()}로 변환하기';
    if (_tool == 'size') return '이 크기로 만들기';
    if (_tool == 'compress' && _limitError == null) {
      final limit = _selectedLimit;
      if (limit != null) return '${_limitLabel(limit)} 이하로 만들기';
    }
    return '사진 만들기';
  }

  Widget _bottomAction() {
    final resultMode = _screen == 'result' || _screen == 'storedExport';
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),
        child: resultMode
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      final compact = constraints.maxWidth < 330 ||
                          scale > 1.2;
                      final gallery = FilledButton.icon(
                        key: const ValueKey('picdori-save-gallery'),
                        onPressed: (_saving || _busy) ? null : _saveGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('사진첩 저장'),
                      );
                      final file = OutlinedButton.icon(
                        key: const ValueKey('picdori-save-file'),
                        onPressed: (_saving || _busy) ? null : _saveFile,
                        icon: const Icon(Icons.folder_outlined),
                        label: const Text('파일 저장'),
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [gallery, const SizedBox(height: 6), file],
                        );
                      }
                      return Row(children: [
                        Expanded(child: gallery),
                        const SizedBox(width: 9),
                        Expanded(child: file),
                      ]);
                    },
                  ),
                  TextButton.icon(
                    onPressed: (_saving || _busy) ? null : _share,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('공유하기'),
                  ),
                ],
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 51, minWidth: double.infinity,
                ),
                child: FilledButton.icon(
                  key: const ValueKey('picdori-make'),
                  onPressed: (_busy || _saving ||
                          _pixelError != null || _limitError != null)
                      ? null : _convert,
                  icon: _busy
                      ? const SizedBox(width: 19, height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_forward_rounded),
                  label: Text(_makeLabel, textAlign: TextAlign.center),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHome = _screen == 'home';
    final viewingResult = _screen == 'result' || _screen == 'storedExport';
    final editing = _screen == 'edit' || viewingResult;
    final showNavigation = _screen != 'edit' ||
        MediaQuery.viewInsetsOf(context).bottom == 0;
    final activeIndex = switch (_screen) {
      'files' || 'detail' || 'storedExport' => 1,
      'history' => 2,
      'settings' || 'trash' || 'storage' => 3,
      _ => 0,
    };
    return PopScope<Object?>(
      canPop: isHome && !_busy && !_saving,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || isHome || _busy || _saving) return;
        if (_screen == 'storedExport') {
          setState(() => _screen = 'detail');
        } else if (_screen == 'result') {
          _returnToEditor();
        } else if (_screen == 'edit') {
          _returnHome();
        } else if (_screen == 'detail') {
          _selectTab(1);
        } else if (_screen == 'trash' || _screen == 'storage') {
          _selectTab(3);
        } else {
          _selectTab(0);
        }
      },
      child: Scaffold(
        backgroundColor: PicdoriColors.background,
        appBar: (isHome || _screen == 'files' ||
            _screen == 'history' || _screen == 'settings') ? null : AppBar(
          leading: IconButton(
            tooltip: '뒤로 가기',
            onPressed: (_busy || _saving) ? null : () {
              if (_screen == 'storedExport') { setState(() => _screen = 'detail'); }
              else if (_screen == 'result') { _returnToEditor(); }
              else if (_screen == 'edit') { _returnHome(); }
              else if (_screen == 'detail') { _selectTab(1); }
              else { _selectTab(3); }
            },
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(switch (_screen) {
            'edit' => _toolTitle,
            'result' => '변환 결과',
            'storedExport' => '저장·공유하기',
            'detail' => '파일 상세',
            'trash' => '최근 삭제',
            'storage' => '저장 공간',
            _ => '픽도리',
          }),
        ),
        body: SafeArea(
          bottom: false,
          child: isHome
            ? SingleChildScrollView(
                child: PicdoriBentoHome(onSelect: _openTool,
                  onSettings: () => _selectTab(3)))
            : editing
              ? (viewingResult ? _resultBody() : _editorBody())
              : _archiveScreen(),
        ),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          if (editing && _source != null)
            DecoratedBox(
              decoration: const BoxDecoration(
                color: PicdoriColors.paper,
                border: Border(top: BorderSide(color: PicdoriColors.outline)),
              ),
              child: _bottomAction(),
            ),
          if (showNavigation) NavigationBar(
            height: 68,
            selectedIndex: activeIndex,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: _selectTab,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home), label: '홈'),
              NavigationDestination(icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder), label: '내 파일'),
              NavigationDestination(icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history), label: '최근 작업'),
              NavigationDestination(icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings), label: '설정'),
            ],
          ),
        ]),
      ),
    );
  }
}

class _TransparencyGrid extends CustomPainter {
  const _TransparencyGrid();

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 8.0;
    final paint = Paint()..color = const Color(0xFFEAE6E0);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var row = 0; row * tile < size.height; row++) {
      for (var col = row % 2; col * tile < size.width; col += 2) {
        canvas.drawRect(Rect.fromLTWH(col * tile, row * tile, tile, tile), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TransparencyGrid oldDelegate) => false;
}
