import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'note.dart';
import 'note_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesApp());
}

const ink = Color(0xFF101C19);
const canvas = Color(0xFFF6F8F5);
const accent = Color(0xFF23AD76);
const muted = Color(0xFF6B7D74);
const categories = ['Совещание', 'Клиент', 'Проект', 'Конференция', 'Личное', 'Другое'];

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nspire Notes', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: accent, primary: const Color(0xFF117D54), surface: Colors.white),
      appBarTheme: const AppBarTheme(backgroundColor: canvas, foregroundColor: ink),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFDCE5DF))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFDCE5DF))),
      ),
    ),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final repo = NoteRepository();
  final search = TextEditingController();
  List<Note> notes = [];
  bool busy = true;
  String filter = 'Все';
  DateTime? dateFilter;

  @override void initState() { super.initState(); _refresh(); search.addListener(_rerender); }
  void _rerender() { if (mounted) setState(() {}); }
  @override void dispose() { search.dispose(); repo.dispose(); super.dispose(); }

  Future<void> _refresh() async {
    try {
      final data = await repo.all();
      if (mounted) setState(() { notes = data; busy = false; });
    } catch (e) {
      if (mounted) { setState(() => busy = false); _message('Ошибка базы данных: $e'); }
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  List<Note> get visible {
    final query = search.text.trim().toLowerCase();
    return notes.where((n) {
      if (filter != 'Все' && n.category != filter) return false;
      if (dateFilter != null && !DateUtils.isSameDay(dateFilter, n.eventAt)) return false;
      if (query.isEmpty) return true;
      final date = DateFormat('dd.MM.yyyy HH:mm').format(n.eventAt);
      return ('${n.title} ${n.content} ${n.category} $date').toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openEditor([Note? original]) async {
    final edited = await Navigator.of(context).push<Note>(MaterialPageRoute(
      builder: (_) => EditNoteScreen(note: original),
    ));
    if (edited == null) return;
    try { await repo.save(edited); await _refresh(); _message(original == null ? 'Заметка создана' : 'Изменения сохранены'); }
    catch (e) { _message('Не удалось сохранить: $e'); }
  }

  Future<void> _confirmDelete(Note note) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Удалить заметку?'), content: Text('«${note.title}» будет удалена без возможности отмены.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить'))],
    ));
    if (confirmed != true || note.id == null) return;
    try { await repo.delete(note.id!); await _refresh(); _message('Заметка удалена'); }
    catch (e) { _message('Не удалось удалить: $e'); }
  }

  Future<void> _exportJson() async {
    try {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/nspire_notes_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
      final file = File(path);
      await file.writeAsString(serializeNotes(notes), flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: 'Резервная копия Nspire Notes'));
    } catch (e) { if (mounted) _message('Ошибка экспорта: $e'); }
  }

  Future<void> _importJson() async {
    try {
      final selected = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (selected == null || selected.files.isEmpty) return;
      final picked = selected.files.single;
      if (picked.size > 5000000) throw const FormatException('Файл превышает 5 МБ');
      final bytes = picked.bytes ?? (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) throw const FormatException('Не удалось прочитать файл');
      final content = utf8.decode(bytes);
      final parsed = deserializeNotes(content);
      if (!mounted) return;
      final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Импорт заметок'),
        content: Text('Добавить ${parsed.length} заметок из JSON? Существующие заметки останутся. Повторный импорт создаст дубликаты.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Импортировать'))],
      ));
      if (confirm != true) return;
      await repo.importMany(parsed);
      await _refresh();
      _message('Импортировано: ${parsed.length}');
    } catch (e) { if (mounted) _message('Не удалось импортировать: $e'); }
  }

  Future<void> _chooseDate() async {
    final chosen = await showDatePicker(context: context, initialDate: dateFilter ?? DateTime.now(),
      firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (chosen != null) setState(() => dateFilter = chosen);
  }

  @override Widget build(BuildContext context) {
    final filtered = visible;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(), backgroundColor: ink, foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded), label: const Text('Новая заметка'),
      ),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.edit_note_rounded, color: Color(0xFF60E5AC), size: 29)),
              const SizedBox(width: 10),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('nspire notes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
                Text('WORKSPACE / MEETING NOTES', style: TextStyle(fontSize: 9, letterSpacing: 1.4, color: muted, fontWeight: FontWeight.w700)),
              ])),
              PopupMenuButton<String>(tooltip: 'Данные', icon: const Icon(Icons.more_horiz_rounded, color: ink),
                onSelected: (v) => v == 'export' ? _exportJson() : _importJson(), itemBuilder: (_) => [
                  const PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.upload_file), title: Text('Экспорт JSON'), dense: true)),
                  const PopupMenuItem(value: 'import', child: ListTile(leading: Icon(Icons.download_rounded), title: Text('Импорт JSON'), dense: true)),
                ]),
            ]),
            const SizedBox(height: 28),
            const Text('Всё важное.\nВ одном месте.', style: TextStyle(fontSize: 33, height: 1.13, letterSpacing: -1, fontWeight: FontWeight.w800, color: ink)),
            const SizedBox(height: 8),
            const Text('Идеи, встречи и решения команды Nspire Dev.', style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 22),
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
              color: ink, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFF64E5AD), size: 34),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${notes.length} заметок', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                  const Text('Сохраняются локально в SQLite', style: TextStyle(color: Color(0xFFAABEB3), fontSize: 11)),
                ])),
                const Icon(Icons.verified_user_outlined, color: Color(0xFF64E5AD)),
              ]),
            ),
            const SizedBox(height: 22),
            TextField(controller: search, decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded), hintText: 'Поиск по названию, тексту, дате...',
              contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 14))),
            const SizedBox(height: 13),
            SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final cat in ['Все', ...categories]) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
                label: Text(cat), selected: filter == cat,
                onSelected: (_) => setState(() => filter = cat),
              )),
            ])),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton.icon(onPressed: _chooseDate, icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(dateFilter == null ? 'Фильтр по дате' : DateFormat('dd.MM.yyyy').format(dateFilter!))),
              if (dateFilter != null) IconButton(tooltip: 'Сбросить дату', onPressed: () => setState(() => dateFilter = null), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Ваши заметки', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ink)),
              Text('${filtered.length} найдено', style: const TextStyle(fontSize: 12, color: muted)),
            ]),
            const SizedBox(height: 10),
          ]))),
          if (busy) const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (filtered.isEmpty) SliverFillRemaining(hasScrollBody: false, child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.note_alt_outlined, color: muted, size: 55),
            const SizedBox(height: 12),
            Text(notes.isEmpty ? 'Заметок пока нет' : 'Ничего не найдено', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(notes.isEmpty ? 'Создайте первую заметку о встрече.' : 'Попробуйте изменить условия поиска.', textAlign: TextAlign.center, style: const TextStyle(color: muted)),
          ])))
          else SliverPadding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 100), sliver: SliverList.builder(
            itemCount: filtered.length,
            itemBuilder: (_, index) {
              final n = filtered[index];
              return Card(color: Colors.white, elevation: 0, margin: const EdgeInsets.only(bottom: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE3EAE4))),
                child: InkWell(borderRadius: BorderRadius.circular(18), onTap: () => _openEditor(n), child: Padding(padding: const EdgeInsets.all(17), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFE8F6EF), borderRadius: BorderRadius.circular(8)), child: Text(n.category, style: const TextStyle(color: Color(0xFF127C54), fontSize: 11, fontWeight: FontWeight.w700))),
                    const Spacer(),
                    if (n.pinned) const Icon(Icons.push_pin_rounded, size: 17, color: accent),
                    IconButton(tooltip: 'Изменить', onPressed: () => _openEditor(n), icon: const Icon(Icons.edit_outlined, size: 18)),
                    IconButton(tooltip: 'Удалить', onPressed: () => _confirmDelete(n), icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFA14D4D))),
                  ]),
                  const SizedBox(height: 3),
                  Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: ink)),
                  if (n.content.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(n.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5, color: muted)),
                  ],
                  const SizedBox(height: 15),
                  Row(children: [const Icon(Icons.schedule_rounded, size: 15, color: muted), const SizedBox(width: 6), Text(DateFormat('dd.MM.yyyy · HH:mm').format(n.eventAt), style: const TextStyle(color: muted, fontSize: 12))]),
                ]))),
              );
            },
          )),
        ]),
      ))),
    );
  }
}

class EditNoteScreen extends StatefulWidget {
  final Note? note;
  const EditNoteScreen({super.key, this.note});
  @override State<EditNoteScreen> createState() => _EditNoteScreenState();
}

class _EditNoteScreenState extends State<EditNoteScreen> {
  final form = GlobalKey<FormState>();
  late final TextEditingController titleController;
  late final TextEditingController contentController;
  late DateTime eventAt;
  late String category;
  late bool pinned;

  @override void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.note?.title ?? '');
    contentController = TextEditingController(text: widget.note?.content ?? '');
    eventAt = widget.note?.eventAt ?? DateTime.now();
    category = widget.note?.category ?? 'Совещание';
    pinned = widget.note?.pinned ?? false;
  }

  @override void dispose() { titleController.dispose(); contentController.dispose(); super.dispose(); }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(context: context, initialDate: eventAt,
        firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(eventAt));
    if (time == null) return;
    setState(() => eventAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  void _save() {
    if (!form.currentState!.validate()) return;
    Navigator.of(context).pop(Note(
      id: widget.note?.id, title: titleController.text.trim(),
      content: contentController.text.trim(), category: category,
      eventAt: eventAt, updatedAt: DateTime.now(), pinned: pinned,
    ));
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.note == null ? 'Новая заметка' : 'Редактировать заметку')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700), child: Form(
      key: form, child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Заголовок', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
        const SizedBox(height: 8),
        TextFormField(controller: titleController, maxLength: 120, textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Например, встреча с клиентом'),
          validator: (s) => s == null || s.trim().isEmpty ? 'Введите заголовок' : null),
        const SizedBox(height: 16),
        const Text('Категория', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: category, items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() => category = v ?? 'Другое')),
        const SizedBox(height: 18),
        const Text('Дата и время мероприятия', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _pickDateTime, icon: const Icon(Icons.event), label: Text(DateFormat('dd.MM.yyyy · HH:mm').format(eventAt)),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16), alignment: Alignment.centerLeft)),
        const SizedBox(height: 18),
        const Text('Содержание', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
        const SizedBox(height: 8),
        TextFormField(controller: contentController, minLines: 7, maxLines: 16, maxLength: 100000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Важные решения, задачи, участники встречи...')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Закрепить заметку'),
          secondary: const Icon(Icons.push_pin_outlined), value: pinned, onChanged: (v) => setState(() => pinned = v)),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined),
          label: const Text('Сохранить заметку'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54))),
      ]),
    ))),
  );
}
