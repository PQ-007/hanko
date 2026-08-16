// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
class $PendingAnswersTable extends PendingAnswers
    with TableInfo<$PendingAnswersTable, PendingAnswer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingAnswersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _logIdMeta = const VerificationMeta('logId');
  @override
  late final GeneratedColumn<String> logId = GeneratedColumn<String>(
    'log_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<String> rating = GeneratedColumn<String>(
    'rating',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _answeredAtMeta = const VerificationMeta(
    'answeredAt',
  );
  @override
  late final GeneratedColumn<DateTime> answeredAt = GeneratedColumn<DateTime>(
    'answered_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    logId,
    cardId,
    rating,
    durationMs,
    answeredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_answers';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingAnswer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('log_id')) {
      context.handle(
        _logIdMeta,
        logId.isAcceptableOrUnknown(data['log_id']!, _logIdMeta),
      );
    } else if (isInserting) {
      context.missing(_logIdMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    } else if (isInserting) {
      context.missing(_ratingMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('answered_at')) {
      context.handle(
        _answeredAtMeta,
        answeredAt.isAcceptableOrUnknown(data['answered_at']!, _answeredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_answeredAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {logId};
  @override
  PendingAnswer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingAnswer(
      logId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}log_id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rating'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      answeredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}answered_at'],
      )!,
    );
  }

  @override
  $PendingAnswersTable createAlias(String alias) {
    return $PendingAnswersTable(attachedDatabase, alias);
  }
}

class PendingAnswer extends DataClass implements Insertable<PendingAnswer> {
  final String logId;
  final String cardId;
  final String rating;
  final int? durationMs;
  final DateTime answeredAt;
  const PendingAnswer({
    required this.logId,
    required this.cardId,
    required this.rating,
    this.durationMs,
    required this.answeredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['log_id'] = Variable<String>(logId);
    map['card_id'] = Variable<String>(cardId);
    map['rating'] = Variable<String>(rating);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['answered_at'] = Variable<DateTime>(answeredAt);
    return map;
  }

  PendingAnswersCompanion toCompanion(bool nullToAbsent) {
    return PendingAnswersCompanion(
      logId: Value(logId),
      cardId: Value(cardId),
      rating: Value(rating),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      answeredAt: Value(answeredAt),
    );
  }

  factory PendingAnswer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingAnswer(
      logId: serializer.fromJson<String>(json['logId']),
      cardId: serializer.fromJson<String>(json['cardId']),
      rating: serializer.fromJson<String>(json['rating']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      answeredAt: serializer.fromJson<DateTime>(json['answeredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'logId': serializer.toJson<String>(logId),
      'cardId': serializer.toJson<String>(cardId),
      'rating': serializer.toJson<String>(rating),
      'durationMs': serializer.toJson<int?>(durationMs),
      'answeredAt': serializer.toJson<DateTime>(answeredAt),
    };
  }

  PendingAnswer copyWith({
    String? logId,
    String? cardId,
    String? rating,
    Value<int?> durationMs = const Value.absent(),
    DateTime? answeredAt,
  }) => PendingAnswer(
    logId: logId ?? this.logId,
    cardId: cardId ?? this.cardId,
    rating: rating ?? this.rating,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    answeredAt: answeredAt ?? this.answeredAt,
  );
  PendingAnswer copyWithCompanion(PendingAnswersCompanion data) {
    return PendingAnswer(
      logId: data.logId.present ? data.logId.value : this.logId,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      rating: data.rating.present ? data.rating.value : this.rating,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      answeredAt: data.answeredAt.present
          ? data.answeredAt.value
          : this.answeredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingAnswer(')
          ..write('logId: $logId, ')
          ..write('cardId: $cardId, ')
          ..write('rating: $rating, ')
          ..write('durationMs: $durationMs, ')
          ..write('answeredAt: $answeredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(logId, cardId, rating, durationMs, answeredAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingAnswer &&
          other.logId == this.logId &&
          other.cardId == this.cardId &&
          other.rating == this.rating &&
          other.durationMs == this.durationMs &&
          other.answeredAt == this.answeredAt);
}

class PendingAnswersCompanion extends UpdateCompanion<PendingAnswer> {
  final Value<String> logId;
  final Value<String> cardId;
  final Value<String> rating;
  final Value<int?> durationMs;
  final Value<DateTime> answeredAt;
  final Value<int> rowid;
  const PendingAnswersCompanion({
    this.logId = const Value.absent(),
    this.cardId = const Value.absent(),
    this.rating = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.answeredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingAnswersCompanion.insert({
    required String logId,
    required String cardId,
    required String rating,
    this.durationMs = const Value.absent(),
    required DateTime answeredAt,
    this.rowid = const Value.absent(),
  }) : logId = Value(logId),
       cardId = Value(cardId),
       rating = Value(rating),
       answeredAt = Value(answeredAt);
  static Insertable<PendingAnswer> custom({
    Expression<String>? logId,
    Expression<String>? cardId,
    Expression<String>? rating,
    Expression<int>? durationMs,
    Expression<DateTime>? answeredAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (logId != null) 'log_id': logId,
      if (cardId != null) 'card_id': cardId,
      if (rating != null) 'rating': rating,
      if (durationMs != null) 'duration_ms': durationMs,
      if (answeredAt != null) 'answered_at': answeredAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingAnswersCompanion copyWith({
    Value<String>? logId,
    Value<String>? cardId,
    Value<String>? rating,
    Value<int?>? durationMs,
    Value<DateTime>? answeredAt,
    Value<int>? rowid,
  }) {
    return PendingAnswersCompanion(
      logId: logId ?? this.logId,
      cardId: cardId ?? this.cardId,
      rating: rating ?? this.rating,
      durationMs: durationMs ?? this.durationMs,
      answeredAt: answeredAt ?? this.answeredAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (logId.present) {
      map['log_id'] = Variable<String>(logId.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (rating.present) {
      map['rating'] = Variable<String>(rating.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (answeredAt.present) {
      map['answered_at'] = Variable<DateTime>(answeredAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingAnswersCompanion(')
          ..write('logId: $logId, ')
          ..write('cardId: $cardId, ')
          ..write('rating: $rating, ')
          ..write('durationMs: $durationMs, ')
          ..write('answeredAt: $answeredAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedCardsTable extends CachedCards
    with TableInfo<$CachedCardsTable, CachedCard> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<String> wordId = GeneratedColumn<String>(
    'word_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deckIdMeta = const VerificationMeta('deckId');
  @override
  late final GeneratedColumn<String> deckId = GeneratedColumn<String>(
    'deck_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateMeta = const VerificationMeta(
    'template',
  );
  @override
  late final GeneratedColumn<String> template = GeneratedColumn<String>(
    'template',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _learningStepMeta = const VerificationMeta(
    'learningStep',
  );
  @override
  late final GeneratedColumn<int> learningStep = GeneratedColumn<int>(
    'learning_step',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<DateTime> dueAt = GeneratedColumn<DateTime>(
    'due_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intervalDaysMeta = const VerificationMeta(
    'intervalDays',
  );
  @override
  late final GeneratedColumn<int> intervalDays = GeneratedColumn<int>(
    'interval_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repetitionsMeta = const VerificationMeta(
    'repetitions',
  );
  @override
  late final GeneratedColumn<int> repetitions = GeneratedColumn<int>(
    'repetitions',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _easeFactorMeta = const VerificationMeta(
    'easeFactor',
  );
  @override
  late final GeneratedColumn<double> easeFactor = GeneratedColumn<double>(
    'ease_factor',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _termMeta = const VerificationMeta('term');
  @override
  late final GeneratedColumn<String> term = GeneratedColumn<String>(
    'term',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readingMeta = const VerificationMeta(
    'reading',
  );
  @override
  late final GeneratedColumn<String> reading = GeneratedColumn<String>(
    'reading',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _meaningMeta = const VerificationMeta(
    'meaning',
  );
  @override
  late final GeneratedColumn<String> meaning = GeneratedColumn<String>(
    'meaning',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _meaningMnMeta = const VerificationMeta(
    'meaningMn',
  );
  @override
  late final GeneratedColumn<String> meaningMn = GeneratedColumn<String>(
    'meaning_mn',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioPathMeta = const VerificationMeta(
    'audioPath',
  );
  @override
  late final GeneratedColumn<String> audioPath = GeneratedColumn<String>(
    'audio_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    cardId,
    wordId,
    deckId,
    template,
    state,
    learningStep,
    dueAt,
    intervalDays,
    repetitions,
    easeFactor,
    term,
    reading,
    meaning,
    meaningMn,
    audioPath,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedCard> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('word_id')) {
      context.handle(
        _wordIdMeta,
        wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_wordIdMeta);
    }
    if (data.containsKey('deck_id')) {
      context.handle(
        _deckIdMeta,
        deckId.isAcceptableOrUnknown(data['deck_id']!, _deckIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deckIdMeta);
    }
    if (data.containsKey('template')) {
      context.handle(
        _templateMeta,
        template.isAcceptableOrUnknown(data['template']!, _templateMeta),
      );
    } else if (isInserting) {
      context.missing(_templateMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('learning_step')) {
      context.handle(
        _learningStepMeta,
        learningStep.isAcceptableOrUnknown(
          data['learning_step']!,
          _learningStepMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_learningStepMeta);
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    } else if (isInserting) {
      context.missing(_dueAtMeta);
    }
    if (data.containsKey('interval_days')) {
      context.handle(
        _intervalDaysMeta,
        intervalDays.isAcceptableOrUnknown(
          data['interval_days']!,
          _intervalDaysMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_intervalDaysMeta);
    }
    if (data.containsKey('repetitions')) {
      context.handle(
        _repetitionsMeta,
        repetitions.isAcceptableOrUnknown(
          data['repetitions']!,
          _repetitionsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_repetitionsMeta);
    }
    if (data.containsKey('ease_factor')) {
      context.handle(
        _easeFactorMeta,
        easeFactor.isAcceptableOrUnknown(data['ease_factor']!, _easeFactorMeta),
      );
    } else if (isInserting) {
      context.missing(_easeFactorMeta);
    }
    if (data.containsKey('term')) {
      context.handle(
        _termMeta,
        term.isAcceptableOrUnknown(data['term']!, _termMeta),
      );
    } else if (isInserting) {
      context.missing(_termMeta);
    }
    if (data.containsKey('reading')) {
      context.handle(
        _readingMeta,
        reading.isAcceptableOrUnknown(data['reading']!, _readingMeta),
      );
    }
    if (data.containsKey('meaning')) {
      context.handle(
        _meaningMeta,
        meaning.isAcceptableOrUnknown(data['meaning']!, _meaningMeta),
      );
    }
    if (data.containsKey('meaning_mn')) {
      context.handle(
        _meaningMnMeta,
        meaningMn.isAcceptableOrUnknown(data['meaning_mn']!, _meaningMnMeta),
      );
    }
    if (data.containsKey('audio_path')) {
      context.handle(
        _audioPathMeta,
        audioPath.isAcceptableOrUnknown(data['audio_path']!, _audioPathMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cardId};
  @override
  CachedCard map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCard(
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      wordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}word_id'],
      )!,
      deckId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deck_id'],
      )!,
      template: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      learningStep: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}learning_step'],
      )!,
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_at'],
      )!,
      intervalDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interval_days'],
      )!,
      repetitions: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repetitions'],
      )!,
      easeFactor: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ease_factor'],
      )!,
      term: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}term'],
      )!,
      reading: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reading'],
      ),
      meaning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meaning'],
      ),
      meaningMn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meaning_mn'],
      ),
      audioPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_path'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $CachedCardsTable createAlias(String alias) {
    return $CachedCardsTable(attachedDatabase, alias);
  }
}

class CachedCard extends DataClass implements Insertable<CachedCard> {
  final String cardId;
  final String wordId;
  final String deckId;
  final String template;
  final String state;
  final int learningStep;
  final DateTime dueAt;
  final int intervalDays;
  final int repetitions;
  final double easeFactor;
  final String term;
  final String? reading;
  final String? meaning;
  final String? meaningMn;
  final String? audioPath;
  final int position;
  const CachedCard({
    required this.cardId,
    required this.wordId,
    required this.deckId,
    required this.template,
    required this.state,
    required this.learningStep,
    required this.dueAt,
    required this.intervalDays,
    required this.repetitions,
    required this.easeFactor,
    required this.term,
    this.reading,
    this.meaning,
    this.meaningMn,
    this.audioPath,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['card_id'] = Variable<String>(cardId);
    map['word_id'] = Variable<String>(wordId);
    map['deck_id'] = Variable<String>(deckId);
    map['template'] = Variable<String>(template);
    map['state'] = Variable<String>(state);
    map['learning_step'] = Variable<int>(learningStep);
    map['due_at'] = Variable<DateTime>(dueAt);
    map['interval_days'] = Variable<int>(intervalDays);
    map['repetitions'] = Variable<int>(repetitions);
    map['ease_factor'] = Variable<double>(easeFactor);
    map['term'] = Variable<String>(term);
    if (!nullToAbsent || reading != null) {
      map['reading'] = Variable<String>(reading);
    }
    if (!nullToAbsent || meaning != null) {
      map['meaning'] = Variable<String>(meaning);
    }
    if (!nullToAbsent || meaningMn != null) {
      map['meaning_mn'] = Variable<String>(meaningMn);
    }
    if (!nullToAbsent || audioPath != null) {
      map['audio_path'] = Variable<String>(audioPath);
    }
    map['position'] = Variable<int>(position);
    return map;
  }

  CachedCardsCompanion toCompanion(bool nullToAbsent) {
    return CachedCardsCompanion(
      cardId: Value(cardId),
      wordId: Value(wordId),
      deckId: Value(deckId),
      template: Value(template),
      state: Value(state),
      learningStep: Value(learningStep),
      dueAt: Value(dueAt),
      intervalDays: Value(intervalDays),
      repetitions: Value(repetitions),
      easeFactor: Value(easeFactor),
      term: Value(term),
      reading: reading == null && nullToAbsent
          ? const Value.absent()
          : Value(reading),
      meaning: meaning == null && nullToAbsent
          ? const Value.absent()
          : Value(meaning),
      meaningMn: meaningMn == null && nullToAbsent
          ? const Value.absent()
          : Value(meaningMn),
      audioPath: audioPath == null && nullToAbsent
          ? const Value.absent()
          : Value(audioPath),
      position: Value(position),
    );
  }

  factory CachedCard.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCard(
      cardId: serializer.fromJson<String>(json['cardId']),
      wordId: serializer.fromJson<String>(json['wordId']),
      deckId: serializer.fromJson<String>(json['deckId']),
      template: serializer.fromJson<String>(json['template']),
      state: serializer.fromJson<String>(json['state']),
      learningStep: serializer.fromJson<int>(json['learningStep']),
      dueAt: serializer.fromJson<DateTime>(json['dueAt']),
      intervalDays: serializer.fromJson<int>(json['intervalDays']),
      repetitions: serializer.fromJson<int>(json['repetitions']),
      easeFactor: serializer.fromJson<double>(json['easeFactor']),
      term: serializer.fromJson<String>(json['term']),
      reading: serializer.fromJson<String?>(json['reading']),
      meaning: serializer.fromJson<String?>(json['meaning']),
      meaningMn: serializer.fromJson<String?>(json['meaningMn']),
      audioPath: serializer.fromJson<String?>(json['audioPath']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cardId': serializer.toJson<String>(cardId),
      'wordId': serializer.toJson<String>(wordId),
      'deckId': serializer.toJson<String>(deckId),
      'template': serializer.toJson<String>(template),
      'state': serializer.toJson<String>(state),
      'learningStep': serializer.toJson<int>(learningStep),
      'dueAt': serializer.toJson<DateTime>(dueAt),
      'intervalDays': serializer.toJson<int>(intervalDays),
      'repetitions': serializer.toJson<int>(repetitions),
      'easeFactor': serializer.toJson<double>(easeFactor),
      'term': serializer.toJson<String>(term),
      'reading': serializer.toJson<String?>(reading),
      'meaning': serializer.toJson<String?>(meaning),
      'meaningMn': serializer.toJson<String?>(meaningMn),
      'audioPath': serializer.toJson<String?>(audioPath),
      'position': serializer.toJson<int>(position),
    };
  }

  CachedCard copyWith({
    String? cardId,
    String? wordId,
    String? deckId,
    String? template,
    String? state,
    int? learningStep,
    DateTime? dueAt,
    int? intervalDays,
    int? repetitions,
    double? easeFactor,
    String? term,
    Value<String?> reading = const Value.absent(),
    Value<String?> meaning = const Value.absent(),
    Value<String?> meaningMn = const Value.absent(),
    Value<String?> audioPath = const Value.absent(),
    int? position,
  }) => CachedCard(
    cardId: cardId ?? this.cardId,
    wordId: wordId ?? this.wordId,
    deckId: deckId ?? this.deckId,
    template: template ?? this.template,
    state: state ?? this.state,
    learningStep: learningStep ?? this.learningStep,
    dueAt: dueAt ?? this.dueAt,
    intervalDays: intervalDays ?? this.intervalDays,
    repetitions: repetitions ?? this.repetitions,
    easeFactor: easeFactor ?? this.easeFactor,
    term: term ?? this.term,
    reading: reading.present ? reading.value : this.reading,
    meaning: meaning.present ? meaning.value : this.meaning,
    meaningMn: meaningMn.present ? meaningMn.value : this.meaningMn,
    audioPath: audioPath.present ? audioPath.value : this.audioPath,
    position: position ?? this.position,
  );
  CachedCard copyWithCompanion(CachedCardsCompanion data) {
    return CachedCard(
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      deckId: data.deckId.present ? data.deckId.value : this.deckId,
      template: data.template.present ? data.template.value : this.template,
      state: data.state.present ? data.state.value : this.state,
      learningStep: data.learningStep.present
          ? data.learningStep.value
          : this.learningStep,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      intervalDays: data.intervalDays.present
          ? data.intervalDays.value
          : this.intervalDays,
      repetitions: data.repetitions.present
          ? data.repetitions.value
          : this.repetitions,
      easeFactor: data.easeFactor.present
          ? data.easeFactor.value
          : this.easeFactor,
      term: data.term.present ? data.term.value : this.term,
      reading: data.reading.present ? data.reading.value : this.reading,
      meaning: data.meaning.present ? data.meaning.value : this.meaning,
      meaningMn: data.meaningMn.present ? data.meaningMn.value : this.meaningMn,
      audioPath: data.audioPath.present ? data.audioPath.value : this.audioPath,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedCard(')
          ..write('cardId: $cardId, ')
          ..write('wordId: $wordId, ')
          ..write('deckId: $deckId, ')
          ..write('template: $template, ')
          ..write('state: $state, ')
          ..write('learningStep: $learningStep, ')
          ..write('dueAt: $dueAt, ')
          ..write('intervalDays: $intervalDays, ')
          ..write('repetitions: $repetitions, ')
          ..write('easeFactor: $easeFactor, ')
          ..write('term: $term, ')
          ..write('reading: $reading, ')
          ..write('meaning: $meaning, ')
          ..write('meaningMn: $meaningMn, ')
          ..write('audioPath: $audioPath, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    cardId,
    wordId,
    deckId,
    template,
    state,
    learningStep,
    dueAt,
    intervalDays,
    repetitions,
    easeFactor,
    term,
    reading,
    meaning,
    meaningMn,
    audioPath,
    position,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedCard &&
          other.cardId == this.cardId &&
          other.wordId == this.wordId &&
          other.deckId == this.deckId &&
          other.template == this.template &&
          other.state == this.state &&
          other.learningStep == this.learningStep &&
          other.dueAt == this.dueAt &&
          other.intervalDays == this.intervalDays &&
          other.repetitions == this.repetitions &&
          other.easeFactor == this.easeFactor &&
          other.term == this.term &&
          other.reading == this.reading &&
          other.meaning == this.meaning &&
          other.meaningMn == this.meaningMn &&
          other.audioPath == this.audioPath &&
          other.position == this.position);
}

class CachedCardsCompanion extends UpdateCompanion<CachedCard> {
  final Value<String> cardId;
  final Value<String> wordId;
  final Value<String> deckId;
  final Value<String> template;
  final Value<String> state;
  final Value<int> learningStep;
  final Value<DateTime> dueAt;
  final Value<int> intervalDays;
  final Value<int> repetitions;
  final Value<double> easeFactor;
  final Value<String> term;
  final Value<String?> reading;
  final Value<String?> meaning;
  final Value<String?> meaningMn;
  final Value<String?> audioPath;
  final Value<int> position;
  final Value<int> rowid;
  const CachedCardsCompanion({
    this.cardId = const Value.absent(),
    this.wordId = const Value.absent(),
    this.deckId = const Value.absent(),
    this.template = const Value.absent(),
    this.state = const Value.absent(),
    this.learningStep = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.intervalDays = const Value.absent(),
    this.repetitions = const Value.absent(),
    this.easeFactor = const Value.absent(),
    this.term = const Value.absent(),
    this.reading = const Value.absent(),
    this.meaning = const Value.absent(),
    this.meaningMn = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedCardsCompanion.insert({
    required String cardId,
    required String wordId,
    required String deckId,
    required String template,
    required String state,
    required int learningStep,
    required DateTime dueAt,
    required int intervalDays,
    required int repetitions,
    required double easeFactor,
    required String term,
    this.reading = const Value.absent(),
    this.meaning = const Value.absent(),
    this.meaningMn = const Value.absent(),
    this.audioPath = const Value.absent(),
    required int position,
    this.rowid = const Value.absent(),
  }) : cardId = Value(cardId),
       wordId = Value(wordId),
       deckId = Value(deckId),
       template = Value(template),
       state = Value(state),
       learningStep = Value(learningStep),
       dueAt = Value(dueAt),
       intervalDays = Value(intervalDays),
       repetitions = Value(repetitions),
       easeFactor = Value(easeFactor),
       term = Value(term),
       position = Value(position);
  static Insertable<CachedCard> custom({
    Expression<String>? cardId,
    Expression<String>? wordId,
    Expression<String>? deckId,
    Expression<String>? template,
    Expression<String>? state,
    Expression<int>? learningStep,
    Expression<DateTime>? dueAt,
    Expression<int>? intervalDays,
    Expression<int>? repetitions,
    Expression<double>? easeFactor,
    Expression<String>? term,
    Expression<String>? reading,
    Expression<String>? meaning,
    Expression<String>? meaningMn,
    Expression<String>? audioPath,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cardId != null) 'card_id': cardId,
      if (wordId != null) 'word_id': wordId,
      if (deckId != null) 'deck_id': deckId,
      if (template != null) 'template': template,
      if (state != null) 'state': state,
      if (learningStep != null) 'learning_step': learningStep,
      if (dueAt != null) 'due_at': dueAt,
      if (intervalDays != null) 'interval_days': intervalDays,
      if (repetitions != null) 'repetitions': repetitions,
      if (easeFactor != null) 'ease_factor': easeFactor,
      if (term != null) 'term': term,
      if (reading != null) 'reading': reading,
      if (meaning != null) 'meaning': meaning,
      if (meaningMn != null) 'meaning_mn': meaningMn,
      if (audioPath != null) 'audio_path': audioPath,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedCardsCompanion copyWith({
    Value<String>? cardId,
    Value<String>? wordId,
    Value<String>? deckId,
    Value<String>? template,
    Value<String>? state,
    Value<int>? learningStep,
    Value<DateTime>? dueAt,
    Value<int>? intervalDays,
    Value<int>? repetitions,
    Value<double>? easeFactor,
    Value<String>? term,
    Value<String?>? reading,
    Value<String?>? meaning,
    Value<String?>? meaningMn,
    Value<String?>? audioPath,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return CachedCardsCompanion(
      cardId: cardId ?? this.cardId,
      wordId: wordId ?? this.wordId,
      deckId: deckId ?? this.deckId,
      template: template ?? this.template,
      state: state ?? this.state,
      learningStep: learningStep ?? this.learningStep,
      dueAt: dueAt ?? this.dueAt,
      intervalDays: intervalDays ?? this.intervalDays,
      repetitions: repetitions ?? this.repetitions,
      easeFactor: easeFactor ?? this.easeFactor,
      term: term ?? this.term,
      reading: reading ?? this.reading,
      meaning: meaning ?? this.meaning,
      meaningMn: meaningMn ?? this.meaningMn,
      audioPath: audioPath ?? this.audioPath,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (wordId.present) {
      map['word_id'] = Variable<String>(wordId.value);
    }
    if (deckId.present) {
      map['deck_id'] = Variable<String>(deckId.value);
    }
    if (template.present) {
      map['template'] = Variable<String>(template.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (learningStep.present) {
      map['learning_step'] = Variable<int>(learningStep.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<DateTime>(dueAt.value);
    }
    if (intervalDays.present) {
      map['interval_days'] = Variable<int>(intervalDays.value);
    }
    if (repetitions.present) {
      map['repetitions'] = Variable<int>(repetitions.value);
    }
    if (easeFactor.present) {
      map['ease_factor'] = Variable<double>(easeFactor.value);
    }
    if (term.present) {
      map['term'] = Variable<String>(term.value);
    }
    if (reading.present) {
      map['reading'] = Variable<String>(reading.value);
    }
    if (meaning.present) {
      map['meaning'] = Variable<String>(meaning.value);
    }
    if (meaningMn.present) {
      map['meaning_mn'] = Variable<String>(meaningMn.value);
    }
    if (audioPath.present) {
      map['audio_path'] = Variable<String>(audioPath.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedCardsCompanion(')
          ..write('cardId: $cardId, ')
          ..write('wordId: $wordId, ')
          ..write('deckId: $deckId, ')
          ..write('template: $template, ')
          ..write('state: $state, ')
          ..write('learningStep: $learningStep, ')
          ..write('dueAt: $dueAt, ')
          ..write('intervalDays: $intervalDays, ')
          ..write('repetitions: $repetitions, ')
          ..write('easeFactor: $easeFactor, ')
          ..write('term: $term, ')
          ..write('reading: $reading, ')
          ..write('meaning: $meaning, ')
          ..write('meaningMn: $meaningMn, ')
          ..write('audioPath: $audioPath, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDb extends GeneratedDatabase {
  _$LocalDb(QueryExecutor e) : super(e);
  $LocalDbManager get managers => $LocalDbManager(this);
  late final $PendingAnswersTable pendingAnswers = $PendingAnswersTable(this);
  late final $CachedCardsTable cachedCards = $CachedCardsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    pendingAnswers,
    cachedCards,
  ];
}

typedef $$PendingAnswersTableCreateCompanionBuilder =
    PendingAnswersCompanion Function({
      required String logId,
      required String cardId,
      required String rating,
      Value<int?> durationMs,
      required DateTime answeredAt,
      Value<int> rowid,
    });
typedef $$PendingAnswersTableUpdateCompanionBuilder =
    PendingAnswersCompanion Function({
      Value<String> logId,
      Value<String> cardId,
      Value<String> rating,
      Value<int?> durationMs,
      Value<DateTime> answeredAt,
      Value<int> rowid,
    });

class $$PendingAnswersTableFilterComposer
    extends Composer<_$LocalDb, $PendingAnswersTable> {
  $$PendingAnswersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get logId => $composableBuilder(
    column: $table.logId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get answeredAt => $composableBuilder(
    column: $table.answeredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingAnswersTableOrderingComposer
    extends Composer<_$LocalDb, $PendingAnswersTable> {
  $$PendingAnswersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get logId => $composableBuilder(
    column: $table.logId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get answeredAt => $composableBuilder(
    column: $table.answeredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingAnswersTableAnnotationComposer
    extends Composer<_$LocalDb, $PendingAnswersTable> {
  $$PendingAnswersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get logId =>
      $composableBuilder(column: $table.logId, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<String> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get answeredAt => $composableBuilder(
    column: $table.answeredAt,
    builder: (column) => column,
  );
}

class $$PendingAnswersTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $PendingAnswersTable,
          PendingAnswer,
          $$PendingAnswersTableFilterComposer,
          $$PendingAnswersTableOrderingComposer,
          $$PendingAnswersTableAnnotationComposer,
          $$PendingAnswersTableCreateCompanionBuilder,
          $$PendingAnswersTableUpdateCompanionBuilder,
          (
            PendingAnswer,
            BaseReferences<_$LocalDb, $PendingAnswersTable, PendingAnswer>,
          ),
          PendingAnswer,
          PrefetchHooks Function()
        > {
  $$PendingAnswersTableTableManager(_$LocalDb db, $PendingAnswersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingAnswersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingAnswersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingAnswersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> logId = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<String> rating = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<DateTime> answeredAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingAnswersCompanion(
                logId: logId,
                cardId: cardId,
                rating: rating,
                durationMs: durationMs,
                answeredAt: answeredAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String logId,
                required String cardId,
                required String rating,
                Value<int?> durationMs = const Value.absent(),
                required DateTime answeredAt,
                Value<int> rowid = const Value.absent(),
              }) => PendingAnswersCompanion.insert(
                logId: logId,
                cardId: cardId,
                rating: rating,
                durationMs: durationMs,
                answeredAt: answeredAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingAnswersTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $PendingAnswersTable,
      PendingAnswer,
      $$PendingAnswersTableFilterComposer,
      $$PendingAnswersTableOrderingComposer,
      $$PendingAnswersTableAnnotationComposer,
      $$PendingAnswersTableCreateCompanionBuilder,
      $$PendingAnswersTableUpdateCompanionBuilder,
      (
        PendingAnswer,
        BaseReferences<_$LocalDb, $PendingAnswersTable, PendingAnswer>,
      ),
      PendingAnswer,
      PrefetchHooks Function()
    >;
typedef $$CachedCardsTableCreateCompanionBuilder =
    CachedCardsCompanion Function({
      required String cardId,
      required String wordId,
      required String deckId,
      required String template,
      required String state,
      required int learningStep,
      required DateTime dueAt,
      required int intervalDays,
      required int repetitions,
      required double easeFactor,
      required String term,
      Value<String?> reading,
      Value<String?> meaning,
      Value<String?> meaningMn,
      Value<String?> audioPath,
      required int position,
      Value<int> rowid,
    });
typedef $$CachedCardsTableUpdateCompanionBuilder =
    CachedCardsCompanion Function({
      Value<String> cardId,
      Value<String> wordId,
      Value<String> deckId,
      Value<String> template,
      Value<String> state,
      Value<int> learningStep,
      Value<DateTime> dueAt,
      Value<int> intervalDays,
      Value<int> repetitions,
      Value<double> easeFactor,
      Value<String> term,
      Value<String?> reading,
      Value<String?> meaning,
      Value<String?> meaningMn,
      Value<String?> audioPath,
      Value<int> position,
      Value<int> rowid,
    });

class $$CachedCardsTableFilterComposer
    extends Composer<_$LocalDb, $CachedCardsTable> {
  $$CachedCardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get wordId => $composableBuilder(
    column: $table.wordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deckId => $composableBuilder(
    column: $table.deckId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get template => $composableBuilder(
    column: $table.template,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get learningStep => $composableBuilder(
    column: $table.learningStep,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intervalDays => $composableBuilder(
    column: $table.intervalDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repetitions => $composableBuilder(
    column: $table.repetitions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get easeFactor => $composableBuilder(
    column: $table.easeFactor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get term => $composableBuilder(
    column: $table.term,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reading => $composableBuilder(
    column: $table.reading,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meaning => $composableBuilder(
    column: $table.meaning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get meaningMn => $composableBuilder(
    column: $table.meaningMn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedCardsTableOrderingComposer
    extends Composer<_$LocalDb, $CachedCardsTable> {
  $$CachedCardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get wordId => $composableBuilder(
    column: $table.wordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deckId => $composableBuilder(
    column: $table.deckId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get template => $composableBuilder(
    column: $table.template,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get learningStep => $composableBuilder(
    column: $table.learningStep,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intervalDays => $composableBuilder(
    column: $table.intervalDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repetitions => $composableBuilder(
    column: $table.repetitions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get easeFactor => $composableBuilder(
    column: $table.easeFactor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get term => $composableBuilder(
    column: $table.term,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reading => $composableBuilder(
    column: $table.reading,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meaning => $composableBuilder(
    column: $table.meaning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meaningMn => $composableBuilder(
    column: $table.meaningMn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedCardsTableAnnotationComposer
    extends Composer<_$LocalDb, $CachedCardsTable> {
  $$CachedCardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<String> get wordId =>
      $composableBuilder(column: $table.wordId, builder: (column) => column);

  GeneratedColumn<String> get deckId =>
      $composableBuilder(column: $table.deckId, builder: (column) => column);

  GeneratedColumn<String> get template =>
      $composableBuilder(column: $table.template, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get learningStep => $composableBuilder(
    column: $table.learningStep,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<int> get intervalDays => $composableBuilder(
    column: $table.intervalDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get repetitions => $composableBuilder(
    column: $table.repetitions,
    builder: (column) => column,
  );

  GeneratedColumn<double> get easeFactor => $composableBuilder(
    column: $table.easeFactor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get term =>
      $composableBuilder(column: $table.term, builder: (column) => column);

  GeneratedColumn<String> get reading =>
      $composableBuilder(column: $table.reading, builder: (column) => column);

  GeneratedColumn<String> get meaning =>
      $composableBuilder(column: $table.meaning, builder: (column) => column);

  GeneratedColumn<String> get meaningMn =>
      $composableBuilder(column: $table.meaningMn, builder: (column) => column);

  GeneratedColumn<String> get audioPath =>
      $composableBuilder(column: $table.audioPath, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$CachedCardsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $CachedCardsTable,
          CachedCard,
          $$CachedCardsTableFilterComposer,
          $$CachedCardsTableOrderingComposer,
          $$CachedCardsTableAnnotationComposer,
          $$CachedCardsTableCreateCompanionBuilder,
          $$CachedCardsTableUpdateCompanionBuilder,
          (
            CachedCard,
            BaseReferences<_$LocalDb, $CachedCardsTable, CachedCard>,
          ),
          CachedCard,
          PrefetchHooks Function()
        > {
  $$CachedCardsTableTableManager(_$LocalDb db, $CachedCardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedCardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedCardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> cardId = const Value.absent(),
                Value<String> wordId = const Value.absent(),
                Value<String> deckId = const Value.absent(),
                Value<String> template = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> learningStep = const Value.absent(),
                Value<DateTime> dueAt = const Value.absent(),
                Value<int> intervalDays = const Value.absent(),
                Value<int> repetitions = const Value.absent(),
                Value<double> easeFactor = const Value.absent(),
                Value<String> term = const Value.absent(),
                Value<String?> reading = const Value.absent(),
                Value<String?> meaning = const Value.absent(),
                Value<String?> meaningMn = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedCardsCompanion(
                cardId: cardId,
                wordId: wordId,
                deckId: deckId,
                template: template,
                state: state,
                learningStep: learningStep,
                dueAt: dueAt,
                intervalDays: intervalDays,
                repetitions: repetitions,
                easeFactor: easeFactor,
                term: term,
                reading: reading,
                meaning: meaning,
                meaningMn: meaningMn,
                audioPath: audioPath,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cardId,
                required String wordId,
                required String deckId,
                required String template,
                required String state,
                required int learningStep,
                required DateTime dueAt,
                required int intervalDays,
                required int repetitions,
                required double easeFactor,
                required String term,
                Value<String?> reading = const Value.absent(),
                Value<String?> meaning = const Value.absent(),
                Value<String?> meaningMn = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => CachedCardsCompanion.insert(
                cardId: cardId,
                wordId: wordId,
                deckId: deckId,
                template: template,
                state: state,
                learningStep: learningStep,
                dueAt: dueAt,
                intervalDays: intervalDays,
                repetitions: repetitions,
                easeFactor: easeFactor,
                term: term,
                reading: reading,
                meaning: meaning,
                meaningMn: meaningMn,
                audioPath: audioPath,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedCardsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $CachedCardsTable,
      CachedCard,
      $$CachedCardsTableFilterComposer,
      $$CachedCardsTableOrderingComposer,
      $$CachedCardsTableAnnotationComposer,
      $$CachedCardsTableCreateCompanionBuilder,
      $$CachedCardsTableUpdateCompanionBuilder,
      (CachedCard, BaseReferences<_$LocalDb, $CachedCardsTable, CachedCard>),
      CachedCard,
      PrefetchHooks Function()
    >;

class $LocalDbManager {
  final _$LocalDb _db;
  $LocalDbManager(this._db);
  $$PendingAnswersTableTableManager get pendingAnswers =>
      $$PendingAnswersTableTableManager(_db, _db.pendingAnswers);
  $$CachedCardsTableTableManager get cachedCards =>
      $$CachedCardsTableTableManager(_db, _db.cachedCards);
}
