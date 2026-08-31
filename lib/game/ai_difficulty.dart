/// Niveaux de jeu de l'ordinateur, du plus tendre au plus impitoyable.
///
/// Ce que chaque niveau change se joue sur trois leviers, et TROIS SEULEMENT :
///
///   * [blunderRate] — la part de coups joués au hasard plutôt qu'au mieux.
///     C'est l'erreur VOLONTAIRE : elle n'existe que pour rendre les niveaux
///     bas battables.
///   * [riskAware]  — l'ordinateur retire-t-il des points à une case où un
///     adversaire pourrait le capturer au tour suivant ?
///   * [lookahead]  — pèse-t-il, en plus, la position qui RÉSULTE du coup :
///     ses pions qui deviennent vulnérables, et les pions adverses qu'il
///     pourra menacer depuis sa nouvelle case ?
///
/// Ce qu'aucun niveau ne change, jamais : le dé. `pickDiceValue` ne sait
/// rien de la difficulté, et l'ordinateur tire dans la même urne que
/// l'humain. Un niveau élevé ne gagne pas parce qu'il a de meilleurs dés,
/// il gagne parce qu'il ne se trompe pas.
enum AiDifficulty {
  /// Joue presque au hasard. Laisse passer des captures, ne se presse pas
  /// de sortir ses pions. Le niveau où l'on apprend les règles.
  debutant(
    label: 'Débutant',
    blunderRate: 0.70,
    riskAware: false,
    lookahead: 0,
    summary: 'Joue presque au hasard et laisse passer des captures.',
  ),

  /// Stratégie de base : il voit les captures évidentes et sort ses pions
  /// sur un 6, mais ne regarde pas plus loin que le coup en cours et se
  /// trompe encore un coup sur cinq.
  moyen(
    label: 'Moyen',
    blunderRate: 0.20,
    riskAware: false,
    lookahead: 0,
    summary: 'Captures évidentes et sorties sur 6, sans anticipation.',
  ),

  /// La stratégie complète, sans erreur : capture, arrivée à la maison,
  /// couloir, cases sûres, et refus de se poser à portée d'un adversaire.
  expert(
    label: 'Expert',
    blunderRate: 0.0,
    riskAware: true,
    lookahead: 0,
    summary: 'Stratégie complète, aucune erreur volontaire.',
  ),

  /// Expert, plus l'anticipation : avant de choisir, il évalue la position
  /// qui suivra son coup — quels pions à lui deviennent prenables, et
  /// lesquels des adversaires il pourra menacer.
  grandMaitre(
    label: 'Grand Maître',
    blunderRate: 0.0,
    riskAware: true,
    lookahead: 250,
    summary: 'Évalue la position qui suit son coup, risques compris.',
  ),

  /// Même lecture que le Grand Maître, mais elle pèse bien plus lourd dans
  /// sa décision : il ne prend jamais un risque qu'il pouvait éviter, et
  /// saisit toute occasion de mettre un adversaire en danger.
  imbattable(
    label: 'Imbattable',
    blunderRate: 0.0,
    riskAware: true,
    lookahead: 500,
    summary: 'Aucune erreur, sécurité et menace pesées au maximum.',
  );

  const AiDifficulty({
    required this.label,
    required this.blunderRate,
    required this.riskAware,
    required this.lookahead,
    required this.summary,
  });

  /// Nom affiché dans le panneau des règles.
  final String label;

  /// Probabilité, entre 0 et 1, de jouer un coup au hasard parmi les coups
  /// légaux au lieu du meilleur. 0 = ne se trompe jamais.
  final double blunderRate;

  /// Retire des points à une case d'arrivée exposée à une capture adverse.
  final bool riskAware;

  /// Poids maximal, en points, de l'évaluation de la position d'APRÈS le
  /// coup. 0 = pas d'anticipation du tout.
  final int lookahead;

  /// Une phrase, affichée sous le nom du niveau.
  final String summary;

  /// Niveau appliqué au lancement de la partie.
  static const AiDifficulty defaultLevel = AiDifficulty.moyen;
}
