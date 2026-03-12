// Represents a single "Root" (T/F option) for the Medical UI
class RootItem {
  final String id;
  final String text;
  final String answer;
  final String info;

  RootItem({
    required this.id,
    required this.text,
    required this.answer,
    required this.info,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'answer': answer,
        'info': info,
      };

  factory RootItem.fromJson(Map<String, dynamic> json) => RootItem(
        id: json['id'] ?? '',
        text: json['text'] ?? '',
        answer: json['answer'] ?? '',
        info: json['info'] ?? '',
      );
}

// Universal Question Model handling BOTH Medical and Science formats
class QuestionModel {
  final String id;
  final String subject; // Also acts as Course Code for Science (e.g., MTH 202)
  final String topic;
  final String year;
  final String stem; // The main question text
  
  // --- MEDICAL SPECIFIC ---
  final List<RootItem> roots;

  // --- SCIENCE / MATH / BIO SPECIFIC ---
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final String answer; // A, B, C, or D
  final String explanation;
  final String imageUrl;
  final String gapContent; // For Biology [[answer|hint]]
  final bool isScience;

  QuestionModel({
    required this.id,
    required this.subject,
    required this.topic,
    required this.year,
    required this.stem,
    required this.roots,
    this.optionA = '',
    this.optionB = '',
    this.optionC = '',
    this.optionD = '',
    this.answer = '',
    this.explanation = '',
    this.imageUrl = '',
    this.gapContent = '',
    this.isScience = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'topic': topic,
        'year': year,
        'stem': stem,
        'roots': roots.map((r) => r.toJson()).toList(),
        'optionA': optionA,
        'optionB': optionB,
        'optionC': optionC,
        'optionD': optionD,
        'answer': answer,
        'explanation': explanation,
        'imageUrl': imageUrl,
        'gapContent': gapContent,
        'isScience': isScience,
      };

  factory QuestionModel.fromJson(Map<String, dynamic> json) => QuestionModel(
        id: json['id'] ?? '',
        subject: json['subject'] ?? '',
        topic: json['topic'] ?? '',
        year: json['year'] ?? '',
        stem: json['stem'] ?? '',
        roots: (json['roots'] as List?)?.map((r) => RootItem.fromJson(r)).toList() ?? [],
        optionA: json['optionA'] ?? '',
        optionB: json['optionB'] ?? '',
        optionC: json['optionC'] ?? '',
        optionD: json['optionD'] ?? '',
        answer: json['answer'] ?? '',
        explanation: json['explanation'] ?? '',
        imageUrl: json['imageUrl'] ?? '',
        gapContent: json['gapContent'] ?? '',
        isScience: json['isScience'] ?? false,
      );
}