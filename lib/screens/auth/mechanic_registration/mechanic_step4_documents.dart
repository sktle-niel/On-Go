import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/auth_widgets.dart';
import '../../../data/registration_draft.dart';
import '../../../utils/step_navigator.dart';
import 'mechanic_step5_verification.dart';

// Requires the file_picker package. Add to pubspec.yaml:
//   file_picker: ^8.1.4   (check pub.dev for latest version)

class MechanicStep4Documents extends StatefulWidget {
  const MechanicStep4Documents({super.key});

  @override
  State<MechanicStep4Documents> createState() =>
      _MechanicStep4DocumentsState();
}

class _MechanicStep4DocumentsState extends State<MechanicStep4Documents> {
  final _draft = RegistrationDraft.instance;

  PlatformFile? _validIdFile;
  PlatformFile? _ncIiFile;
  List<PlatformFile> _certificateFiles = [];

  bool _validIdError = false;
  bool _ncIiError    = false;

  @override
  void initState() {
    super.initState();
    _restoreFromDraft();
  }

  /// Re-hydrate PlatformFile stubs from saved paths.
  /// PlatformFile only needs [name] and [path] for display — size/bytes are
  /// not available after a restart, so we show 0 bytes gracefully.
  void _restoreFromDraft() {
    final validId = _draft.resolveFile(_draft.validIdPath);
    if (validId != null) {
      _validIdFile = PlatformFile(
        name: _draft.validIdPath.split('/').last,
        path: _draft.validIdPath,
        size: 0,
      );
    }
    final ncIi = _draft.resolveFile(_draft.ncIiPath);
    if (ncIi != null) {
      _ncIiFile = PlatformFile(
        name: _draft.ncIiPath.split('/').last,
        path: _draft.ncIiPath,
        size: 0,
      );
    }
    _certificateFiles = _draft.certPaths
        .where((path) => _draft.resolveFile(path) != null)
        .map((path) => PlatformFile(
              name: path.split('/').last,
              path: path,
              size: 0,
            ))
        .toList();
  }

  void _autosave() {
    _draft.validIdPath = _validIdFile?.path ?? '';
    _draft.ncIiPath    = _ncIiFile?.path ?? '';
    _draft.certPaths   = _certificateFiles
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();
    _draft.saveStep4();
  }

  Future<PlatformFile?> _pickSingleFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  Future<List<PlatformFile>> _pickMultipleFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return [];
    return result.files;
  }

  Future<void> _pickValidId() async {
    final file = await _pickSingleFile();
    if (file != null) {
      setState(() {
        _validIdFile = file;
        _validIdError = false;
      });
      _autosave();
    }
  }

  Future<void> _pickNcIi() async {
    final file = await _pickSingleFile();
    if (file != null) {
      setState(() {
        _ncIiFile = file;
        _ncIiError = false;
      });
      _autosave();
    }
  }

  Future<void> _pickCertificates() async {
    final files = await _pickMultipleFiles();
    if (files.isNotEmpty) {
      setState(() {
        _certificateFiles = [..._certificateFiles, ...files];
      });
      _autosave();
    }
  }

  bool _validateRequired() {
    final validIdMissing = _validIdFile == null;
    final ncIiMissing = _ncIiFile == null;
    setState(() {
      _validIdError = validIdMissing;
      _ncIiError = ncIiMissing;
    });
    return !validIdMissing && !ncIiMissing;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const RegistrationHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: context.layout.pageInsets,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RegistrationStepper(
                    currentStep: 4,
                    highestCompletedStep: _draft.highestCompletedStep,
                    onStepTapped: (step) => goToRegistrationStep(context, step),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Required Documents',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textdark,
                    ),
                  ),
                  const SizedBox(height: 20),

                  _DocumentUploadTile(
                    label: 'Valid ID',
                    buttonLabel: 'UPLOAD VALID ID',
                    icon: Icons.upload_outlined,
                    file: _validIdFile,
                    showError: _validIdError,
                    onPick: _pickValidId,
                    onRemove: () {
                      setState(() => _validIdFile = null);
                      _autosave();
                    },
                  ),
                  const SizedBox(height: 16),

                  // NCII
                  _DocumentUploadTile(
                    label: 'NC II',
                    buttonLabel: 'UPLOAD NC II',
                    icon: Icons.upload_outlined,
                    file: _ncIiFile,
                    showError: _ncIiError,
                    onPick: _pickNcIi,
                    onRemove: () {
                      setState(() => _ncIiFile = null);
                      _autosave();
                    },
                  ),
                  const SizedBox(height: 16),

                  // Related Certificates (Optional, multiple)
                  _MultiDocumentUploadTile(
                    label: 'Related Certificates (Optional)',
                    buttonLabel: 'UPLOAD CERTIFICATES',
                    icon: Icons.upload_outlined,
                    files: _certificateFiles,
                    onPick: _pickCertificates,
                    onRemoveAt: (index) {
                      setState(() => _certificateFiles =
                          List.of(_certificateFiles)..removeAt(index));
                      _autosave();
                    },
                  ),
                  const SizedBox(height: 28),

                  StepNavButtons(
                    onBack: () => Navigator.pop(context),
                    onNext: () {
                      if (!_validateRequired()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            duration: AppDurations.snackBar,
                            content: Text(
                                'Please upload Valid ID and NCII before continuing.'),
                          ),
                        );
                        return;
                      }
                      _autosave(); // saveStep4 is called inside _autosave
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const MechanicStep5Verification(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatFileSize(int bytes) {
  if (bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  return '${size.toStringAsFixed(size >= 10 || unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
}

IconData _iconForExtension(String? extension) {
  switch ((extension ?? '').toLowerCase()) {
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'heic':
    case 'webp':
      return Icons.image_outlined;
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'doc':
    case 'docx':
      return Icons.description_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

class _DocumentUploadTile extends StatelessWidget {
  final String label;
  final String buttonLabel;
  final IconData icon;
  final PlatformFile? file;
  final bool showError;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _DocumentUploadTile({
    required this.label,
    required this.buttonLabel,
    required this.icon,
    required this.file,
    required this.onPick,
    required this.onRemove,
    this.showError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Both single-document tiles are required documents.
        OnGoFieldLabel(label, isRequired: true),
        const SizedBox(height: 8),
        if (file == null)
          OutlinedButton.icon(
            icon: Icon(icon, size: 18),
            label: Text(buttonLabel),
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.info,
              side: BorderSide(
                  color: showError ? AppColors.error : AppColors.info),
              minimumSize: const Size(double.infinity, 48),
              shape: const StadiumBorder(),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.textdark.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(_iconForExtension(file!.extension),
                    size: 20, color: AppColors.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      if (file!.size > 0)
                        Text(
                          _formatFileSize(file!.size),
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onRemove,
                  tooltip: 'Remove',
                ),
              ],
            ),
          ),
        if (showError)
          Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'This document is required',
              style: TextStyle(fontSize: 11, color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

class _MultiDocumentUploadTile extends StatelessWidget {
  final String label;
  final String buttonLabel;
  final IconData icon;
  final List<PlatformFile> files;
  final VoidCallback onPick;
  final void Function(int index) onRemoveAt;

  const _MultiDocumentUploadTile({
    required this.label,
    required this.buttonLabel,
    required this.icon,
    required this.files,
    required this.onPick,
    required this.onRemoveAt,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnGoFieldLabel(label),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: Icon(icon, size: 18),
          label: Text(buttonLabel),
          onPressed: onPick,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.info,
            side: BorderSide(color: AppColors.info),
            minimumSize: const Size(double.infinity, 48),
            shape: const StadiumBorder(),
          ),
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...List.generate(files.length, (i) {
            final f = files[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.textdark.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(_iconForExtension(f.extension),
                        size: 20, color: AppColors.info),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                          if (f.size > 0)
                            Text(
                              _formatFileSize(f.size),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textdark.withValues(alpha: 0.55)),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => onRemoveAt(i),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}