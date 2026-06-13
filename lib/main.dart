import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(const InterviewApp());
}

class InterviewApp extends StatelessWidget {
  const InterviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Interview Prep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF534AB7),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF534AB7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ─── DATA MODELS ────────────────────────────────────────────────────────────

class StudySession {
  final int id;
  final String date;
  final String learned;
  final List<String> tags;
  final String difficulties;
  final String questionTypes;

  StudySession({
    required this.id,
    required this.date,
    required this.learned,
    required this.tags,
    required this.difficulties,
    required this.questionTypes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'learned': learned,
        'tags': tags,
        'difficulties': difficulties,
        'questionTypes': questionTypes,
      };

  factory StudySession.fromJson(Map<String, dynamic> j) => StudySession(
        id: j['id'],
        date: j['date'],
        learned: j['learned'],
        tags: List<String>.from(j['tags']),
        difficulties: j['difficulties'] ?? '',
        questionTypes: j['questionTypes'] ?? '',
      );
}

class AppData {
  List<StudySession> sessions;
  String difficulty;
  int questionCount;
  int totalSessions;
  List<int> scores;

  AppData({
    this.sessions = const [],
    this.difficulty = "Boshlang'ich",
    this.questionCount = 10,
    this.totalSessions = 0,
    this.scores = const [],
  });

  Map<String, dynamic> toJson() => {
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'difficulty': difficulty,
        'questionCount': questionCount,
        'totalSessions': totalSessions,
        'scores': scores,
      };

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        sessions: (j['sessions'] as List).map((s) => StudySession.fromJson(s)).toList(),
        difficulty: j['difficulty'] ?? "Boshlang'ich",
        questionCount: j['questionCount'] ?? 10,
        totalSessions: j['totalSessions'] ?? 0,
        scores: List<int>.from(j['scores'] ?? []),
      );
}

// ─── DATA SERVICE ────────────────────────────────────────────────────────────

class DataService {
  static const _key = 'app_data';
  static AppData _data = AppData();

  static AppData get data => _data;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      _data = AppData.fromJson(jsonDecode(raw));
    }
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_data.toJson()));
  }

  static Future<void> addSession(StudySession s) async {
    _data = AppData(
      sessions: [..._data.sessions, s],
      difficulty: _data.difficulty,
      questionCount: _data.questionCount,
      totalSessions: _data.totalSessions,
      scores: _data.scores,
    );
    await save();
  }

  static Future<void> recordSession(int avgScore) async {
    _data = AppData(
      sessions: _data.sessions,
      difficulty: _data.difficulty,
      questionCount: _data.questionCount,
      totalSessions: _data.totalSessions + 1,
      scores: [..._data.scores, avgScore],
    );
    await save();
  }

  static Future<void> updateSettings({String? difficulty, int? questionCount}) async {
    _data = AppData(
      sessions: _data.sessions,
      difficulty: difficulty ?? _data.difficulty,
      questionCount: questionCount ?? _data.questionCount,
      totalSessions: _data.totalSessions,
      scores: _data.scores,
    );
    await save();
  }

  static int get avgScore {
    if (_data.scores.isEmpty) return 0;
    return _data.scores.reduce((a, b) => a + b) ~/ _data.scores.length;
  }
}

// ─── AI SERVICE ──────────────────────────────────────────────────────────────

class AIService {
  static const _apiUrl = 'https://api.anthropic.com/v1/messages';

  static Future<Map<String, dynamic>> generateQuestion(
      List<String> prevQuestions) async {
    final allLearned = DataService.data.sessions
        .map((s) =>
            'Sana: ${s.date}\nMavzu: ${s.learned}${s.difficulties.isNotEmpty ? '\nQiyinchiliklar: ${s.difficulties}' : ''}${s.tags.isNotEmpty ? '\nKategoriyalar: ${s.tags.join(', ')}' : ''}')
        .join('\n\n---\n\n');

    final customTypes = DataService.data.sessions
        .where((s) => s.questionTypes.isNotEmpty)
        .map((s) => s.questionTypes)
        .join(', ');

    final prompt = '''Sen Flutter va Dart bo'yicha professional interview o'tkazuvchisan. O'zbek tilida javob ber.

Foydalanuvchi o'rgangan mavzular:
$allLearned

Qiyinlik darajasi: ${DataService.data.difficulty}
${customTypes.isNotEmpty ? 'Maxsus savol turlari: $customTypes' : ''}
${prevQuestions.isNotEmpty ? 'Avval berilgan savollar (takrorlamaslik uchun):\n${prevQuestions.join('\n')}' : ''}

Endi bitta yangi Flutter/Dart interview savoli tuzib ber. Faqat JSON format:
{"question":"Savol matni","category":"Kategoriya","expectedPoints":["point1","point2","point3"]}''';

    return await _callApi(prompt);
  }

  static Future<Map<String, dynamic>> evaluateAnswer(
      String question, List<String> expectedPoints, String answer) async {
    final prompt = '''Sen Flutter/Dart interview baholovchisan. O'zbek tilida baholab ber.

Savol: $question
Kutilgan nuqtalar: ${expectedPoints.join(', ')}
Javob: $answer

Faqat JSON format:
{"score":85,"verdict":"Yaxshi","feedback":"Batafsil fikr 2-3 gap","missing":"Nima qoldi"}

Score 0-100. Verdict: "A'lo"(90+),"Yaxshi"(70-89),"O'rtacha"(50-69),"Zaif"(50-)''';

    return await _callApi(prompt);
  }

  static Future<String> getHint(String question) async {
    final prompt =
        "Flutter/Dart savoliga 1-2 gapda maslahat ber, javobni berma. O'zbek tilida.\n\nSavol: $question";
    final result = await _callApi(prompt, expectJson: false);
    return result['text'] ?? '';
  }

  static Future<Map<String, dynamic>> _callApi(String prompt,
      {bool expectJson = true}) async {
    final res = await http.post(
      Uri.parse(_apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': 'claude-sonnet-4-6',
        'max_tokens': 1000,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      }),
    );

    final data = jsonDecode(res.body);
    final text =
        (data['content'] as List).map((c) => c['text'] ?? '').join('');

    if (!expectJson) return {'text': text};

    final clean = text.replaceAll(RegExp(r'```json|```'), '').trim();
    return jsonDecode(clean);
  }
}

// ─── COLORS ──────────────────────────────────────────────────────────────────

const kPurple = Color(0xFF534AB7);
const kPurpleLight = Color(0xFFEEEDFE);
const kPurpleDark = Color(0xFF3C3489);

// ─── HOME SCREEN ─────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    DataService.load().then((_) => setState(() => _loading = false));
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final pages = [
      _HomePage(onRefresh: _refresh),
      const AddSessionPage(),
      const TopicsPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) async {
          if (i == 1) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AddSessionPage(onSaved: _refresh)),
            );
          } else if (i == 2 && DataService.data.sessions.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Avval mavzu qo'shing!")),
            );
            setState(() => _tab = 1);
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AddSessionPage(onSaved: _refresh)),
            );
          } else {
            setState(() => _tab = i);
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Bosh sahifa'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: "Qo'shish"),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Mavzular'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Sozlamalar'),
        ],
      ),
    );
  }
}

// ─── HOME PAGE ───────────────────────────────────────────────────────────────

class _HomePage extends StatelessWidget {
  final VoidCallback onRefresh;
  const _HomePage({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final d = DataService.data;
    final avg = DataService.avgScore;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPurple, kPurpleDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text('Xush kelibsiz!', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    const Text('Interview Tayyorgarlik', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    const Text('Flutter & Dart', style: TextStyle(color: Colors.white60, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _StatCard('${d.sessions.length}', 'Mavzu'),
                    const SizedBox(width: 10),
                    _StatCard('${d.totalSessions}', 'Sessiya'),
                    const SizedBox(width: 10),
                    _StatCard(d.scores.isEmpty ? '—' : '$avg%', 'O\'rtacha'),
                  ]),
                  const SizedBox(height: 20),
                  const Text('AMALLAR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Colors.grey)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _ActionCard(Icons.add_circle_outline, 'Bugungi mavzu', "O'rganganlarni kiriting", () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => AddSessionPage(onSaved: onRefresh)));
                    })),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionCard(Icons.play_circle_outline, 'Interview', 'AI savol beradi', () {
                      if (d.sessions.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Avval mavzu qo'shing!")));
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute(builder: (_) => InterviewScreen(onFinished: onRefresh)));
                    })),
                  ]),
                  const SizedBox(height: 20),
                  const Text("SO'NGGI SESSIYALAR", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Colors.grey)),
                  const SizedBox(height: 10),
                  if (d.sessions.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text("Hali mavzu yo'q. Qo'shish tugmasini bosing!", style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    ...d.sessions.reversed.take(5).map((s) => _RecentItem(s)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: kPurple)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ActionCard(this.icon, this.title, this.subtitle, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withAlpha(40)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: kPurple, size: 28),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
    );
  }
}

class _RecentItem extends StatelessWidget {
  final StudySession s;
  const _RecentItem(this.s);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withAlpha(30)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.learned.length > 45 ? '${s.learned.substring(0, 45)}...' : s.learned,
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 2),
          Text(s.date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ])),
        if (s.tags.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: kPurpleLight, borderRadius: BorderRadius.circular(20)),
            child: Text(s.tags.first, style: const TextStyle(fontSize: 11, color: kPurpleDark, fontWeight: FontWeight.w500)),
          ),
      ]),
    );
  }
}

// ─── ADD SESSION PAGE ────────────────────────────────────────────────────────

class AddSessionPage extends StatefulWidget {
  final VoidCallback? onSaved;
  const AddSessionPage({super.key, this.onSaved});

  @override
  State<AddSessionPage> createState() => _AddSessionPageState();
}

class _AddSessionPageState extends State<AddSessionPage> {
  final _learnedCtrl = TextEditingController();
  final _difficultiesCtrl = TextEditingController();
  final _questionTypesCtrl = TextEditingController();
  final _tags = <String>{};
  bool _saving = false;

  static const _allTags = [
    'Widgets', 'State management', 'Dart basics', 'Navigation',
    'Async/Await', 'HTTP/API', 'Animation', 'Testing', 'Performance', 'Architecture'
  ];

  Future<void> _save() async {
    if (_learnedCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Iltimos, o'rganganlaringizni kiriting!")),
      );
      return;
    }
    setState(() => _saving = true);
    await DataService.addSession(StudySession(
      id: DateTime.now().millisecondsSinceEpoch,
      date: DateTime.now().toString().substring(0, 10),
      learned: _learnedCtrl.text.trim(),
      tags: _tags.toList(),
      difficulties: _difficultiesCtrl.text.trim(),
      questionTypes: _questionTypesCtrl.text.trim(),
    ));
    widget.onSaved?.call();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bugungi o'rganganlar"), backgroundColor: kPurple, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label("Bugun nima o'rgandingiz?", required: true),
          const SizedBox(height: 6),
          TextField(
            controller: _learnedCtrl,
            maxLines: 5,
            decoration: _inputDeco("Masalan: Flutter StatefulWidget, State management..."),
          ),
          const SizedBox(height: 16),
          _label('Kategoriya'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _allTags.map((t) {
            final sel = _tags.contains(t);
            return FilterChip(
              label: Text(t),
              selected: sel,
              onSelected: (_) => setState(() => sel ? _tags.remove(t) : _tags.add(t)),
              selectedColor: kPurpleLight,
              checkmarkColor: kPurpleDark,
              labelStyle: TextStyle(color: sel ? kPurpleDark : null, fontSize: 13),
            );
          }).toList()),
          const SizedBox(height: 16),
          _label('Qiyinchiliklar (ixtiyoriy)'),
          const SizedBox(height: 6),
          TextField(
            controller: _difficultiesCtrl,
            maxLines: 3,
            decoration: _inputDeco('Nima tushunarsiz bo\'ldi?'),
          ),
          const SizedBox(height: 16),
          _label('Maxsus savol turlari (ixtiyoriy)'),
          const SizedBox(height: 6),
          TextField(
            controller: _questionTypesCtrl,
            maxLines: 2,
            decoration: _inputDeco('Masalan: ko\'proq coding questions, nazariy savollar...'),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
              label: const Text('Saqlash', style: TextStyle(fontSize: 15)),
              style: FilledButton.styleFrom(
                backgroundColor: kPurple,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _label(String text, {bool required = false}) => RichText(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
          children: required ? const [TextSpan(text: ' *', style: TextStyle(color: Colors.red))] : [],
        ),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPurple)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );
}

// ─── TOPICS PAGE ─────────────────────────────────────────────────────────────

class TopicsPage extends StatelessWidget {
  const TopicsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = DataService.data.sessions.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Barcha mavzularim'), backgroundColor: kPurple, foregroundColor: Colors.white),
      body: sessions.isEmpty
          ? const Center(child: Text("Hali mavzu qo'shilmagan", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sessions.length,
              itemBuilder: (_, i) => _TopicCard(sessions[i]),
            ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  final StudySession s;
  const _TopicCard(this.s);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withAlpha(30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(s.date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Wrap(spacing: 4, children: s.tags.map((t) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: kPurpleLight, borderRadius: BorderRadius.circular(20)),
            child: Text(t, style: const TextStyle(fontSize: 10, color: kPurpleDark)),
          )).toList()),
        ]),
        const SizedBox(height: 8),
        Text(s.learned, style: const TextStyle(fontSize: 14, height: 1.5)),
        if (s.difficulties.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.info_outline, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Expanded(child: Text(s.difficulties, style: const TextStyle(fontSize: 12, color: Colors.grey))),
          ]),
        ],
      ]),
    );
  }
}

// ─── SETTINGS PAGE ───────────────────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final d = DataService.data;
    return Scaffold(
      appBar: AppBar(title: const Text('Sozlamalar'), backgroundColor: kPurple, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('QIYINLIK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: ["Boshlang'ich", "O'rta", "Yuqori"].map((v) {
            final sel = d.difficulty == v;
            return ChoiceChip(
              label: Text(v),
              selected: sel,
              onSelected: (_) async {
                await DataService.updateSettings(difficulty: v);
                setState(() {});
              },
              selectedColor: kPurpleLight,
              labelStyle: TextStyle(color: sel ? kPurpleDark : null),
            );
          }).toList()),
          const SizedBox(height: 20),
          const Text('SAVOL SONI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [5, 10, 15, 20].map((v) {
            final sel = d.questionCount == v;
            return ChoiceChip(
              label: Text('$v ta'),
              selected: sel,
              onSelected: (_) async {
                await DataService.updateSettings(questionCount: v);
                setState(() {});
              },
              selectedColor: kPurpleLight,
              labelStyle: TextStyle(color: sel ? kPurpleDark : null),
            );
          }).toList()),
        ]),
      ),
    );
  }
}

// ─── INTERVIEW SCREEN ────────────────────────────────────────────────────────

class InterviewScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const InterviewScreen({super.key, required this.onFinished});

  @override
  State<InterviewScreen> createState() => _InterviewScreenState();
}

class _InterviewScreenState extends State<InterviewScreen> {
  int _qIndex = 0;
  bool _loadingQ = true;
  bool _checking = false;
  bool _answered = false;
  bool _gettingHint = false;
  String? _hint;
  Map<String, dynamic>? _currentQ;
  Map<String, dynamic>? _evaluation;
  final _answerCtrl = TextEditingController();
  final List<String> _prevQuestions = [];
  final List<int> _scores = [];

  int get _total => DataService.data.questionCount;

  @override
  void initState() {
    super.initState();
    _loadQuestion();
  }

  Future<void> _loadQuestion() async {
    setState(() { _loadingQ = true; _answered = false; _evaluation = null; _hint = null; _answerCtrl.clear(); });
    try {
      final q = await AIService.generateQuestion(_prevQuestions);
      _currentQ = q;
      _prevQuestions.add(q['question'] ?? '');
    } catch (e) {
      _currentQ = {
        'question': "Flutter'da StatefulWidget va StatelessWidget farqi nima?",
        'category': 'Widgets',
        'expectedPoints': ['State boshqaruvi', 'Rebuild', 'Performance'],
      };
    }
    setState(() => _loadingQ = false);
  }

  Future<void> _checkAnswer() async {
    if (_answerCtrl.text.trim().isEmpty) return;
    setState(() => _checking = true);
    try {
      final ev = await AIService.evaluateAnswer(
        _currentQ!['question'],
        List<String>.from(_currentQ!['expectedPoints'] ?? []),
        _answerCtrl.text.trim(),
      );
      _evaluation = ev;
      _scores.add((ev['score'] as num).toInt());
    } catch (e) {
      _evaluation = {'score': 70, 'verdict': 'Baholandi', 'feedback': 'Javobingiz qabul qilindi.', 'missing': ''};
      _scores.add(70);
    }
    setState(() { _checking = false; _answered = true; });
  }

  Future<void> _getHint() async {
    setState(() => _gettingHint = true);
    try {
      final hint = await AIService.getHint(_currentQ!['question']);
      setState(() { _hint = hint; _gettingHint = false; });
    } catch (_) {
      setState(() => _gettingHint = false);
    }
  }

  Future<void> _next() async {
    if (_qIndex >= _total - 1) {
      final avg = _scores.isEmpty ? 0 : _scores.reduce((a, b) => a + b) ~/ _scores.length;
      await DataService.recordSession(avg);
      widget.onFinished();
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Interview yakunlandi!"),
            content: Text("O'rtacha balingiz: $avg / 100\n\nZo'r ishlading! Davom eting!"),
            actions: [TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text("Bosh sahifaga"))],
          ),
        );
      }
    } else {
      setState(() => _qIndex++);
      _loadQuestion();
    }
  }

  Color _scoreColor(int score) {
    if (score >= 90) return Colors.green;
    if (score >= 70) return Colors.blue;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_qIndex + 1) / _total;

    return Scaffold(
      appBar: AppBar(
        title: Text('Savol ${_qIndex + 1} / $_total'),
        backgroundColor: kPurple,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: progress, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.white)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Question card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.withAlpha(30)),
            ),
            child: _loadingQ
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: kPurple)))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('SAVOL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(_currentQ?['question'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.5)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: kPurpleLight, borderRadius: BorderRadius.circular(20)),
                      child: Text(_currentQ?['category'] ?? '', style: const TextStyle(fontSize: 11, color: kPurpleDark, fontWeight: FontWeight.w500)),
                    ),
                  ]),
          ),

          if (_hint != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_outline, color: Colors.blue, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_hint!, style: TextStyle(fontSize: 13, color: Colors.blue.shade800))),
              ]),
            ),
          ],

          const SizedBox(height: 16),
          const Text('JAVOBINGIZ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(
            controller: _answerCtrl,
            maxLines: 5,
            enabled: !_answered,
            decoration: InputDecoration(
              hintText: 'Javobingizni shu yerga yozing...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPurple)),
            ),
          ),

          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _answered || _loadingQ || _gettingHint ? null : _getHint,
                icon: _gettingHint ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lightbulb_outline),
                label: const Text('Maslahat'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _answered || _loadingQ || _checking ? null : _checkAnswer,
                icon: _checking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
                label: const Text('Tekshirish'),
                style: FilledButton.styleFrom(backgroundColor: kPurple, padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ]),

          if (_answered && _evaluation != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.withAlpha(30)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _scoreColor((_evaluation!['score'] as num).toInt()).withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _evaluation!['verdict'] ?? '',
                      style: TextStyle(fontWeight: FontWeight.w600, color: _scoreColor((_evaluation!['score'] as num).toInt())),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${_evaluation!['score']} / 100', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ]),
                const SizedBox(height: 10),
                Text(_evaluation!['feedback'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
                if ((_evaluation!['missing'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text("Qo'shish mumkin edi: ${_evaluation!['missing']}", style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _next,
                icon: Icon(_qIndex >= _total - 1 ? Icons.flag_outlined : Icons.arrow_forward),
                label: Text(_qIndex >= _total - 1 ? 'Yakunlash' : 'Keyingi savol'),
                style: FilledButton.styleFrom(backgroundColor: kPurple, padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
