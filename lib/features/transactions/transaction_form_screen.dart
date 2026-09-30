import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/app_error.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/money.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/common.dart';
import '../../domain/entities/finance_transaction.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/liquid.dart';
import '../../shared/widgets/glass.dart';
import '../auth/auth_controller.dart';
import '../map/map_screen.dart';
import '../map/map_service.dart';
import '../moments/location_service.dart';
import '../settings/settings_controller.dart';
import 'photo_preview.dart';

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.initial, this.initialDate});

  final FinanceTransaction? initial;
  final DateTime? initialDate;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final TextEditingController _location;
  late final TextEditingController _lat;
  late final TextEditingController _lng;

  late TxType _type;
  String? _categoryId;
  late DateTime _date;

  Uint8List? _newPhoto;
  String? _localPhoto;
  String? _remotePhoto;
  bool _saving = false;
  bool _locating = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    final currency = ref.read(settingsProvider).currency;
    _type = t?.type ?? TxType.expense;
    _categoryId = t?.categoryId;
    final now = DateTime.now();
    final baseDate = widget.initialDate;
    _date = t?.date ??
        (baseDate != null
            ? DateTime(baseDate.year, baseDate.month, baseDate.day, now.hour, now.minute)
            : now);
    _name = TextEditingController(text: t?.name ?? '');
    final minor = t?.amountMinor;
    _amount = TextEditingController(text: minor == null ? '' : Money.toInput(minor, currency));
    _note = TextEditingController(text: t?.note ?? '');
    _location = TextEditingController(text: t?.locationName ?? '');
    _lat = TextEditingController(text: t?.latitude?.toString() ?? '');
    _lng = TextEditingController(text: t?.longitude?.toString() ?? '');
    _localPhoto = t?.localImagePath;
    _remotePhoto = t?.remoteImagePath;
    // Giao dịch MỚI chưa có toạ độ -> tự lấy vị trí hiện tại. Giao dịch đã có thì giữ
    // nguyên nơi ban đầu; chỉ đổi khi người dùng bấm nút vị trí / chọn trên bản đồ.
    if (t == null && (_lat.text.trim().isEmpty || _lng.text.trim().isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoLocate());
    }
  }

  /// Lấy vị trí hiện tại (tự xin quyền), điền toạ độ + tên địa điểm.
  /// [force] = người dùng bấm nút: ghi đè cả tên địa điểm đã có.
  Future<void> _autoLocate({bool force = false}) async {
    if (_locating || !mounted) return;
    setState(() => _locating = true);
    final fix = await LocationService.current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (fix == null) return;
      _lat.text = fix.lat.toStringAsFixed(6);
      _lng.text = fix.lng.toStringAsFixed(6);
      if (force || _location.text.trim().isEmpty) _location.text = fix.place;
    });
    if (fix == null && force) showSnack(context, context.tr('moment_no_location'));
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _note, _location, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 2400);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() => _newPhoto = bytes);
      // Chụp ảnh cho giao dịch mới -> lấy vị trí nơi chụp nếu chưa có.
      if (source == ImageSource.camera &&
          widget.initial == null &&
          (_lat.text.trim().isEmpty || _location.text.trim().isEmpty)) {
        _autoLocate();
      }
    } catch (e) {
      if (mounted) showError(context, AppError(AppErrorType.storage, cause: e));
    }
  }

  void _removePhoto() {
    setState(() {
      _newPhoto = null;
      _localPhoto = null;
      _remotePhoto = null;
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (t == null) return;
    setState(() => _date = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute));
  }

  Future<void> _pickOnMap() async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    final result = await Navigator.of(context).push<MapPoint>(MaterialPageRoute(
      builder: (_) =>
          MapPickerScreen(initial: lat != null && lng != null ? MapPoint(lat, lng) : null),
    ));
    if (result == null) return;
    setState(() {
      _lat.text = result.lat.toStringAsFixed(6);
      _lng.text = result.lng.toStringAsFixed(6);
    });
    // Chọn trên bản đồ -> tự tra tên địa điểm.
    final place = await LocationService.placeName(result.lat, result.lng);
    if (mounted) setState(() => _location.text = place);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final currency = ref.read(settingsProvider).currency;
    final amount = Money.parse(_amount.text, currency)!;
    final lat = double.tryParse(_lat.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lng.text.trim().replaceAll(',', '.'));
    setState(() => _saving = true);
    final photos = ref.read(photoServiceProvider);
    final repo = ref.read(transactionRepoProvider);
    final oldLocal = widget.initial?.localImagePath;
    try {
      String? local = _localPhoto;
      String? remote = _remotePhoto;
      if (_newPhoto != null) {
        local = await photos.saveCompressed(_newPhoto!);
        remote = null; // ảnh mới -> cần upload lại
      }
      final now = DateTime.now();
      final base = widget.initial ??
          FinanceTransaction(
            id: Ids.newId(),
            userId: ref.read(currentUserIdProvider),
            name: '',
            amountMinor: amount,
            type: _type,
            date: _date,
            createdAt: now,
            updatedAt: now,
          );
      final tx = base.copyWith(
        name: _name.text,
        amountMinor: amount,
        type: _type,
        categoryId: _categoryId,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        date: _date,
        locationName: _location.text.trim().isEmpty ? null : _location.text.trim(),
        latitude: lat,
        longitude: lng,
        localImagePath: local,
        remoteImagePath: remote,
      );
      await repo.save(tx);
      if (oldLocal != null && oldLocal != local) {
        await photos.deleteLocal(oldLocal);
      }
      if (!mounted) return;
      showSnack(context, context.tr('saved'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  Future<void> _delete() async {
    final t = widget.initial;
    if (t == null) return;
    if (!await confirmDelete(context)) return;
    try {
      await ref.read(transactionRepoProvider).delete(t.id);
      if (!mounted) return;
      showSnack(context, context.tr('deleted'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <TxCategory>[];
    final typed = cats.where((c) => c.type == _type).toList();
    final validCategory = typed.any((c) => c.id == _categoryId) ? _categoryId : null;
    final currency = ref.watch(settingsProvider.select((s) => s.currency));

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(_editing ? 'edit_transaction' : 'add_transaction')),
        actions: [
          if (_editing)
            IconButton(
              tooltip: context.tr('delete'),
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              ContentWidth(
                max: 720,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LiquidSegmented<TxType>(
                            segments: [
                              ButtonSegment(
                                value: TxType.expense,
                                icon: const Icon(Icons.arrow_upward),
                                label: Text(context.tr('expense')),
                              ),
                              ButtonSegment(
                                value: TxType.income,
                                icon: const Icon(Icons.arrow_downward),
                                label: Text(context.tr('income')),
                              ),
                            ],
                            selected: {_type},
                            onSelectionChanged: (s) => setState(() {
                              _type = s.first;
                              _categoryId = null;
                            }),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _name,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(labelText: context.tr('tx_name')),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? context.tr('validation_name')
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _amount,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                            ],
                            decoration: InputDecoration(
                              labelText: context.tr('tx_amount'),
                              suffixText: currency.symbol,
                            ),
                            validator: (v) => Money.parse(v ?? '', currency) == null
                                ? context.tr('validation_amount')
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          LabeledDropdown<String?>(
                            label: context.tr('tx_category'),
                            value: validCategory,
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(context.tr('category_uncategorized')),
                              ),
                              for (final c in typed)
                                DropdownMenuItem<String?>(
                                  value: c.id,
                                  child: Row(
                                    children: [
                                      CategoryAvatar(category: c, size: 24),
                                      const SizedBox(width: AppSpacing.sm),
                                      Flexible(
                                        child: Text(categoryLabel(context, c),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() => _categoryId = v),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _pickDate,
                                icon: const Icon(Icons.calendar_today, size: 18),
                                label: Text(formatDate(context, _date)),
                              ),
                              OutlinedButton.icon(
                                onPressed: _pickTime,
                                icon: const Icon(Icons.schedule, size: 18),
                                label: Text(TimeOfDay.fromDateTime(_date).format(context)),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _note,
                            maxLines: 3,
                            minLines: 1,
                            decoration: InputDecoration(
                              labelText: context.tr('tx_note'),
                              helperText: context.tr('optional'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(context.tr('tx_location'),
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: AppSpacing.sm),
                          TextFormField(
                            controller: _location,
                            decoration: InputDecoration(
                              labelText: context.tr('tx_location'),
                              prefixIcon: const Icon(Icons.place_outlined),
                              suffixIcon: _locating
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2)),
                                    )
                                  : IconButton(
                                      tooltip: context.tr('use_current_location'),
                                      icon: const Icon(Icons.my_location_rounded),
                                      onPressed: () => _autoLocate(force: true),
                                    ),
                              helperText: _locating ? context.tr('moment_locating') : null,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _lat,
                                  keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true, signed: true),
                                  decoration: InputDecoration(labelText: context.tr('tx_latitude')),
                                  validator: (_) => _coordError(context),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: TextFormField(
                                  controller: _lng,
                                  keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true, signed: true),
                                  decoration:
                                      InputDecoration(labelText: context.tr('tx_longitude')),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _pickOnMap,
                              icon: const Icon(Icons.map_outlined),
                              label: Text(context.tr('pick_on_map')),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(context.tr('tx_photo'),
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: AppSpacing.sm),
                          PhotoPreview(
                            bytes: _newPhoto,
                            localPath: _localPhoto,
                            remotePath: _remotePhoto,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              if (_isMobile)
                                OutlinedButton.icon(
                                  onPressed: () => _pickPhoto(ImageSource.camera),
                                  icon: const Icon(Icons.photo_camera_outlined),
                                  label: Text(context.tr('take_photo')),
                                ),
                              OutlinedButton.icon(
                                onPressed: () => _pickPhoto(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(context.tr('choose_photo')),
                              ),
                              if (_newPhoto != null || _localPhoto != null || _remotePhoto != null)
                                TextButton.icon(
                                  onPressed: _removePhoto,
                                  icon: const Icon(Icons.close),
                                  label: Text(context.tr('remove_photo')),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: Text(context.tr('save')),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _coordError(BuildContext context) {
    final a = _lat.text.trim();
    final b = _lng.text.trim();
    if (a.isEmpty && b.isEmpty) return null;
    final lat = double.tryParse(a.replaceAll(',', '.'));
    final lng = double.tryParse(b.replaceAll(',', '.'));
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      return context.tr('validation_coordinates');
    }
    return null;
  }
}
