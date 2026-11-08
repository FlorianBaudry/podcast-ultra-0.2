import Foundation

struct KnowledgeFact: Identifiable {
    let id: Int
    let category: String
    let icon: String
    let titleFr: String
    let textFr: String
    let titleEn: String
    let textEn: String
    
    func title(for lang: LangCode) -> String {
        lang == .fr ? titleFr : titleEn
    }
    
    func text(for lang: LangCode) -> String {
        lang == .fr ? textFr : textEn
    }
}

class KnowledgeFactsService: ObservableObject {
    static let shared = KnowledgeFactsService()
    
    @Published private(set) var recentFactIds: [Int] = []
    private let recentFactsKey = "voxstream_recent_knowledge_fact_ids"
    
    private init() {
        if let saved = UserDefaults.standard.array(forKey: recentFactsKey) as? [Int], !saved.isEmpty {
            self.recentFactIds = Array(saved.prefix(5))
        } else {
            self.recentFactIds = [1, 21, 36, 46, 56]
        }
    }
    
    let facts: [KnowledgeFact] = [
        // --- 1 to 20: Astronomie & Physique (Solstice, Espace, Relativité) ---
        KnowledgeFact(
            id: 1,
            category: "Astronomie",
            icon: "sun.max.fill",
            titleFr: "Le Solstice et l'inclinaison terrestre",
            textFr: "Les saisons ne résultent pas de la distance de la Terre au Soleil, mais de son inclinaison axiale de 23,44°. Au solstice d'été boréal, le pôle Nord est orienté au maximum vers le Soleil, offrant le jour le plus long de l'année.",
            titleEn: "Solstices and Earth's Axial Tilt",
            textEn: "Seasons are not caused by Earth's distance to the Sun, but by its 23.44° axial tilt. At the summer solstice, the North Pole points closest to the Sun, creating the longest day of the year."
        ),
        KnowledgeFact(
            id: 2,
            category: "Physique",
            icon: "clock.arrow.circlepath",
            titleFr: "La Relativité du Temps",
            textFr: "Selon la relativité générale d'Einstein, le temps s'écoule plus lentement à proximité d'une masse imposante. Les horloges au niveau de la mer retardent légèrement par rapport à celles placées au sommet de l'Everest.",
            titleEn: "Time Dilation and Relativity",
            textEn: "Under Einstein's general relativity, gravity slows time. Clocks at sea level tick marginally slower than clocks atop Mount Everest."
        ),
        KnowledgeFact(
            id: 3,
            category: "Astrophysique",
            icon: "sparkles",
            titleFr: "Nous sommes faits de poussière d'étoiles",
            textFr: "Pratiquement tous les éléments lourds de notre corps (le fer de notre sang, le calcium de nos os, le carbone de nos cellules) ont été forgés au cœur d'étoiles massives qui ont explosé en supernova il y a des milliards d'années.",
            titleEn: "Forged in Stellar Cores",
            textEn: "Almost every heavy atom in our bodies—the iron in our blood, the calcium in our bones—was synthesized inside exploding supernovae billions of years ago."
        ),
        KnowledgeFact(
            id: 4,
            category: "Physique Quantique",
            icon: "atom",
            titleFr: "Le Vide n'est jamais vide",
            textFr: "En physique quantique, le vide absolu grouille de particules virtuelles qui naissent et s'annihilent en fractions infinitésimales de seconde : ce phénomène crée l'effet Casimir.",
            titleEn: "The Quantum Vacuum",
            textEn: "In quantum field theory, empty space boils with virtual particle pairs appearing and annihilating in fractions of a femtosecond, producing the Casimir effect."
        ),
        KnowledgeFact(
            id: 5,
            category: "Astronomie",
            icon: "moon.stars.fill",
            titleFr: "L'éloignement continu de la Lune",
            textFr: "En raison du frottement des marées océaniques terrestres, la Lune s'éloigne de notre planète à une vitesse d'environ 3,8 centimètres par an.",
            titleEn: "The Receding Moon",
            textEn: "Due to tidal friction transferring orbital energy, the Moon spirals away from Earth at roughly 3.8 centimeters per year."
        ),
        KnowledgeFact(
            id: 6,
            category: "Physique",
            icon: "bolt.fill",
            titleFr: "La Vitesse de la Lumière",
            textFr: "La lumière voyage à 299 792 km/s dans le vide. Un photon du Soleil met environ 8 minutes et 20 secondes pour atteindre la Terre, mais des dizaines de milliers d'années pour sortir du cœur solaire.",
            titleEn: "Speed of Light and Solar Photons",
            textEn: "Light travels at 299,792 km/s. A photon takes 8 minutes 20 seconds to reach Earth from the Sun's surface, but tens of thousands of years to escape the core."
        ),
        KnowledgeFact(
            id: 7,
            category: "Astronomie",
            icon: "globe.americas.fill",
            titleFr: "Ératosthène et le rayon de la Terre",
            textFr: "Vers 240 avant J.-C., Ératosthène calcula la circonférence de la Terre avec une précision impressionnante (moins de 2% d'erreur) en observant simplement l'ombre d'un bâton à Alexandrie le jour du solstice d'été.",
            titleEn: "Eratosthenes and the Earth's Size",
            textEn: "Around 240 BC, Eratosthenes calculated Earth's circumference within 2% accuracy by simply measuring sun shadows in Alexandria at the summer solstice."
        ),
        KnowledgeFact(
            id: 8,
            category: "Physique",
            icon: "thermometer.snowflake",
            titleFr: "Le Zéro Absolu (-273,15 °C)",
            textFr: "À 0 Kelvin (-273,15 °C), l'agitation thermique classique s'arrête complètement. La matière adopte alors des comportements quantiques fascinants comme la supraconductivité et les condensats de Bose-Einstein.",
            titleEn: "Absolute Zero (-273.15°C)",
            textEn: "At 0 Kelvin, all thermal motion halts. Matter exhibits exotic quantum behaviors like zero-resistance superconductivity and Bose-Einstein condensation."
        ),
        KnowledgeFact(
            id: 9,
            category: "Astrophysique",
            icon: "circle.circle",
            titleFr: "Les Trous Noirs et l'Horizon des Événements",
            textFr: "L'horizon des événements d'un trou noir est la frontière au-delà de laquelle même la lumière ne possède pas une vitesse suffisante pour échapper à la courbure de l'espace-temps.",
            titleEn: "Black Hole Event Horizons",
            textEn: "The event horizon marks the boundary where spacetime is curved so severely that escape velocity exceeds the speed of light."
        ),
        KnowledgeFact(
            id: 10,
            category: "Physique",
            icon: "waveform.path.ecg",
            titleFr: "Les Ondes Gravitationnelles",
            textFr: "Prédites par Einstein en 1916 et détectées directement en 2015 par LIGO, les ondes gravitationnelles sont des ondulations du tissu même de l'espace-temps provoquées par la fusion de monstres cosmiques.",
            titleEn: "Gravitational Waves",
            textEn: "Predicted in 1916 and detected by LIGO in 2015, gravitational waves are actual ripples in the fabric of spacetime produced by colliding black holes."
        ),
        KnowledgeFact(
            id: 11,
            category: "Sciences",
            icon: "drop.fill",
            titleFr: "L'étrange anomalie de l'eau",
            textFr: "Contrairement à la majorité des liquides, l'eau atteint sa densité maximale à 4 °C. La glace flotte donc sur l'eau liquide, permettant à la vie aquatique de survivre sous la glace en hiver.",
            titleEn: "Water's Density Anomaly",
            textEn: "Unlike most liquids, water is densest at 4°C. Ice expands and floats, insulating water below and preserving aquatic life through freezing winters."
        ),
        KnowledgeFact(
            id: 12,
            category: "Astrophysique",
            icon: "rays",
            titleFr: "La Fusion Nucléaire du Soleil",
            textFr: "Chaque seconde, le Soleil fusionne 600 millions de tonnes d'hydrogène en hélium, convertissant 4 millions de tonnes de matière en pure énergie selon la célèbre formule E = mc².",
            titleEn: "Solar Fusion Power",
            textEn: "Every second, the Sun fuses 600 million tons of hydrogen into helium, converting 4 million tons of mass directly into radiant energy via E = mc²."
        ),
        KnowledgeFact(
            id: 13,
            category: "Physique",
            icon: "shield.fill",
            titleFr: "Le Bouclier Magnétique Terrestre",
            textFr: "Le noyau externe liquide de la Terre, composé de fer en fusion en rotation, génère un puissant champ magnétique qui nous protège continuellement des vents solaires destructeurs.",
            titleEn: "Earth's Geodynamo",
            textEn: "Convection in Earth's molten iron outer core generates a magnetosphere that shields our atmosphere from stripping by lethal solar winds."
        ),
        KnowledgeFact(
            id: 14,
            category: "Astronomie",
            icon: "eye.fill",
            titleFr: "Regarder le Passé Cosmique",
            textFr: "Lorsque vous contemplez la galaxie d'Andromède à l'œil nu dans une nuit étoilée, vous recevez une lumière émise il y a 2,5 millions d'années, avant même l'apparition de l'Homo erectus.",
            titleEn: "Cosmic Time Travel",
            textEn: "Looking at the Andromeda Galaxy through a telescope reveals photons that started their voyage 2.5 million years ago, before early humans walked the Earth."
        ),
        KnowledgeFact(
            id: 15,
            category: "Physique",
            icon: "battery.100.bolt",
            titleFr: "La Radioactivité Naturelle",
            textFr: "Les bananes contiennent du potassium 40, un isotope radioactif naturel. Une personne moyenne émet elle-même plusieurs milliers de désintégrations radioactives par seconde sans aucun danger.",
            titleEn: "Natural Radioactivity",
            textEn: "Bananas contain Potassium-40, a harmless natural radioisotope. The human body itself emits thousands of radioactive disintegrations every second."
        ),
        KnowledgeFact(
            id: 16,
            category: "Astrophysique",
            icon: "circle.grid.cross.fill",
            titleFr: "Les Étoiles à Neutrons",
            textFr: "Une cuillère à café de matière provenant d'une étoile à neutrons pèserait environ 6 milliards de tonnes sur Terre, soit la masse cumulée de toutes les voitures de la planète.",
            titleEn: "Neutron Star Density",
            textEn: "A single teaspoon of neutron star matter would weigh roughly 6 billion tons on Earth, equivalent to the mass of every motor vehicle in existence."
        ),
        KnowledgeFact(
            id: 17,
            category: "Physique",
            icon: "wind",
            titleFr: "L'Effet Bernoulli et le Vol",
            textFr: "Le profil aérodynamique d'une aile d'avion accélère le flux d'air au-dessus d'elle, réduisant la pression selon le principe de Bernoulli et créant la portance qui permet aux avions de voler.",
            titleEn: "Bernoulli and Aerodynamics",
            textEn: "Air moves faster over the curved top of an airfoil, reducing pressure relative to the bottom and generating aerodynamic lift."
        ),
        KnowledgeFact(
            id: 18,
            category: "Astronomie",
            icon: "calendar",
            titleFr: "L'Équinoxe et l'égalité jour-nuit",
            textFr: "Lors des équinoxes de printemps et d'automne, le Soleil traverse le plan équatorial céleste. Le jour et la nuit ont alors une durée presque parfaitement égale de 12 heures sur l'ensemble de la planète.",
            titleEn: "The Equinox Balance",
            textEn: "At the equinox, the solar terminator aligns perpendicular to Earth's equator, giving every latitude on the planet near-exact 12-hour day and night."
        ),
        KnowledgeFact(
            id: 19,
            category: "Sciences",
            icon: "flame.fill",
            titleFr: "L'Entropie et la Flèche du Temps",
            textFr: "Le deuxième principe de la thermodynamique stipule que l'entropie (le désordre) d'un système isolé augmente toujours, définissant la direction irréversible du cours du temps.",
            titleEn: "Entropy and the Arrow of Time",
            textEn: "The Second Law of Thermodynamics dictates that entropy in an isolated system always increases, giving time its single irreversible forward direction."
        ),
        KnowledgeFact(
            id: 20,
            category: "Astronomie",
            icon: "sparkles.tv",
            titleFr: "L'Écho du Big Bang",
            textFr: "Le fond diffus cosmologique (CMB) baigne l'univers à 2,7 Kelvin. Une fraction de la « neige » sur les anciens téléviseurs analogiques non réglés provenait directement de cet écho originel du Big Bang.",
            titleEn: "The Cosmic Microwave Background",
            textEn: "About 1% of the static on old analog television sets disconnected from antennas was leftover radiation from the Big Bang itself."
        ),

        // --- 21 to 50: Productivité, Psychologie & Efficacité cognitive ---
        KnowledgeFact(
            id: 21,
            category: "Productivité",
            icon: "hourglass",
            titleFr: "La Loi de Parkinson",
            textFr: "« Le travail s'étale de façon à occuper tout le temps disponible pour son achèvement. » Fixer des délais courts et fermes permet d'accomplir une tâche en une fraction du temps habituel.",
            titleEn: "Parkinson's Law",
            textEn: "'Work expands to fill the time available for its completion.' Setting aggressive, strict deadlines eliminates overthinking and drives rapid execution."
        ),
        KnowledgeFact(
            id: 22,
            category: "Neurosciences",
            icon: "brain.head.profile",
            titleFr: "Le Système Glymphatique",
            textFr: "Pendant le sommeil profond, les cellules gliales du cerveau se contractent pour laisser circuler le liquide céphalo-rachidien, évacuant la bêta-amyloïde et les déchets métaboliques de la journée.",
            titleEn: "The Brain's Waste Clearance",
            textEn: "During deep sleep, the brain's glymphatic system expands to flush out toxic metabolic waste products, including amyloid plaques, restoring mental clarity."
        ),
        KnowledgeFact(
            id: 23,
            category: "Productivité",
            icon: "chart.pie.fill",
            titleFr: "Le Principe de Pareto (80/20)",
            textFr: "Dans presque tous les domaines, 80% des résultats proviennent de 20% des efforts. Identifier vos 20% d'actions à fort impact démultiplie votre efficacité sans effort supplémentaire.",
            titleEn: "The Pareto Principle (80/20 Rule)",
            textEn: "80% of outcomes typically stem from 20% of inputs. Ruthlessly prioritizing the vital 20% delivers outsized returns with less exhaustion."
        ),
        KnowledgeFact(
            id: 24,
            category: "Psychologie",
            icon: "arrow.triangle.2.circlepath",
            titleFr: "L'Effet Zeigarnik",
            textFr: "Notre cerveau retient beaucoup mieux les tâches inachevées que les tâches accomplies, ce qui génère de la charge mentale. Noter vos idées sur papier libère immédiatement votre mémoire de travail.",
            titleEn: "The Zeigarnik Effect",
            textEn: "Unfinished tasks occupy active working memory and provoke anxiety. Writing them down signals completion to the brain and instantly restores focus."
        ),
        KnowledgeFact(
            id: 25,
            category: "Biologie",
            icon: "sun.haze.fill",
            titleFr: "La Lumière du Matin et le Cortisol",
            textFr: "Exposer vos yeux à la lumière naturelle du soleil pendant 10 à 15 minutes dès le réveil déclenche le pic sain de cortisol matinal et cale l'horloge biologique pour un sommeil réparateur 16 heures plus tard.",
            titleEn: "Morning Sunlight and Circadian Rhythm",
            textEn: "Viewing natural morning sunlight within an hour of waking resets your master circadian clock, boosting daytime alertness and nighttime melatonin."
        ),
        KnowledgeFact(
            id: 26,
            category: "Productivité",
            icon: "timer",
            titleFr: "Les Cycles Ultradiens de 90 minutes",
            textFr: "Le cerveau humain fonctionne par cycles d'attention soutenue de 90 minutes environ. Après ce délai, le niveau d'énergie chute naturellement : une pause de 15 minutes suffit pour recharger les réserves.",
            titleEn: "Ultradian Rhythm Cycles",
            textEn: "Human focus peaks in 90-minute ultradian cycles. Taking a deliberate 10–15 minute break between deep sessions prevents chronic mental fatigue."
        ),
        KnowledgeFact(
            id: 27,
            category: "Productivité",
            icon: "checkmark.circle.fill",
            titleFr: "La Règle des Deux Minutes",
            textFr: "Issue de la méthode GTD (David Allen) : si une tâche prend moins de deux minutes à accomplir (répondre à un e-mail rapide, ranger un dossier), faites-la immédiatement au lieu de la planifier.",
            titleEn: "The Two-Minute Rule",
            textEn: "From David Allen's Getting Things Done: if an incoming task takes less than two minutes, do it right away instead of cataloging or deferring it."
        ),
        KnowledgeFact(
            id: 28,
            category: "Psychologie",
            icon: "target",
            titleFr: "La Fatigue Décisionnelle",
            textFr: "Chaque décision prise au cours de la journée entame votre réserve de volonté. Automatiser ses routines du matin et ses repas préserve votre énergie mentale pour les choix stratégiques cruciaux.",
            titleEn: "Decision Fatigue",
            textEn: "Every choice drains mental stamina. Simplifying daily trivialities—like clothing and breakfast—reserves cognitive horsepower for major decisions."
        ),
        KnowledgeFact(
            id: 29,
            category: "Productivité",
            icon: "headphones",
            titleFr: "L'État de Flow (Csíkszentmihályi)",
            textFr: "Le « flow » survient lorsque le niveau de défi d'une tâche correspond précisément au niveau de compétence. L'élimination totale des distractions pendant 20 minutes suffit généralement à y entrer.",
            titleEn: "The Psychology of Flow",
            textEn: "Flow occurs when challenge and skill match at high levels. Protecting your workspace from notifications for 20 minutes triggers seamless immersion."
        ),
        KnowledgeFact(
            id: 30,
            category: "Neurosciences",
            icon: "figure.walk",
            titleFr: "La Marche et la Pensée Créative",
            textFr: "Une étude de Stanford a démontré qu'une marche de 15 minutes augmente la créativité et la résolution de problèmes de 60% par rapport à une réflexion en position assise.",
            titleEn: "Walking Boosts Creative Output",
            textEn: "Stanford researchers found walking outdoors increases creative divergent thinking by up to 60% compared to sitting still at a desk."
        ),
        KnowledgeFact(
            id: 31,
            category: "Productivité",
            icon: "calendar.badge.clock",
            titleFr: "Le Time-Blocking",
            textFr: "Allouer des créneaux horaires dédiés dans son calendrier plutôt que d'utiliser une liste de tâches infinie force à arbitrer sur ce qui compte vraiment et protège des interruptions imprévues.",
            titleEn: "Calendar Time-Blocking",
            textEn: "Assigning dedicated blocks on a calendar instead of an open-ended to-do list forces realistic commitments and shields against scope creep."
        ),
        KnowledgeFact(
            id: 32,
            category: "Psychologie",
            icon: "eye.slash.fill",
            titleFr: "Le Coût du Changement de Contexte",
            textFr: "Après une interruption par une notification ou un message, il faut en moyenne 23 minutes et 15 secondes au cerveau pour retrouver le niveau d'immersion initial.",
            titleEn: "Context Switching Overhead",
            textEn: "University of California research shows it takes an average of 23 minutes and 15 seconds to regain deep focus after a single distraction."
        ),
        KnowledgeFact(
            id: 33,
            category: "Neurosciences",
            icon: "pencil.and.outline",
            titleFr: "L'Écriture Manuelle et la Mémorisation",
            textFr: "Prendre des notes à la main active des réseaux neuronaux moteurs et spatiaux plus riches que la frappe sur clavier, renforçant la synthèse conceptuelle et la mémoire à long terme.",
            titleEn: "Handwriting Deepens Encoding",
            textEn: "Writing notes by hand activates motor-spatial cognitive pathways, forcing synthesis and cementing long-term memory far better than typing."
        ),
        KnowledgeFact(
            id: 34,
            category: "Productivité",
            icon: "sun.max",
            titleFr: "Manger le crapaud (Eat the Frog)",
            textFr: "Inspiré par Mark Twain : accomplir la tâche la plus intimidante ou difficile dès le début de votre journée vous libère d'un poids et transforme le reste de la journée en dynamique positive.",
            titleEn: "Eat the Frog First",
            textEn: "Mark Twain noted: tackle your most intimidating task first thing in the morning. Doing so clears mental drag and unlocks daily momentum."
        ),
        KnowledgeFact(
            id: 35,
            category: "Psychologie",
            icon: "chart.line.uptrend.xyaxis",
            titleFr: "L'Effet Dunning-Kruger",
            textFr: "Les débutants dans un domaine ont tendance à surestimer grandement leur maîtrise, tandis que les experts doutent souvent de leurs compétences. La vraie expertise commence par la conscience de son ignorance.",
            titleEn: "The Dunning-Kruger Effect",
            textEn: "Novices often overestimate their grasp of complex subjects, while experts underestimate theirs. Real mastery begins by recognizing knowledge gaps."
        ),

        // --- 36 to 65: Richesse, Économie & Décisions financières ---
        KnowledgeFact(
            id: 36,
            category: "Richesse",
            icon: "chart.line.uptrend.xyaxis.circle.fill",
            titleFr: "Les Intérêts Composés",
            textFr: "Qualifiés par Einstein de « huitième merveille du monde », les intérêts composés permettent à un capital modeste mais réinvesti régulièrement de croître de manière exponentielle avec le temps.",
            titleEn: "Compound Interest Magic",
            textEn: "Often called the eighth wonder of the world: compounding turns regular, patient investments into exponential wealth over long horizons."
        ),
        KnowledgeFact(
            id: 37,
            category: "Finance",
            icon: "number.circle.fill",
            titleFr: "La Règle des 72",
            textFr: "Pour estimer le nombre d'années nécessaires pour doubler votre investissement, divisez 72 par le rendement annuel. À 7% par an, votre capital double environ tous les 10 ans (72 / 7 ≈ 10,3).",
            titleEn: "The Rule of 72",
            textEn: "Divide 72 by your expected annual rate of return to estimate how many years it takes to double your capital. At 7%, money doubles in ~10 years."
        ),
        KnowledgeFact(
            id: 38,
            category: "Économie",
            icon: "hourglass.bottomhalf.filled",
            titleFr: "L'Effet Lindy",
            textFr: "Pour les technologies et les idées non périssables, l'espérance de vie future est proportionnelle à leur âge actuel. Un livre ou un principe lu depuis 50 ans a de fortes chances d'être encore lu dans 50 ans.",
            titleEn: "The Lindy Effect",
            textEn: "For non-perishable ideas and technologies, future life expectancy is proportional to current age. A book relevant for 50 years will likely endure 50 more."
        ),
        KnowledgeFact(
            id: 39,
            category: "Finance",
            icon: "banknote.fill",
            titleFr: "Payez-vous en premier",
            textFr: "Le principe fondamental des finances personnelles : épargnez et investissez automatiquement une part fixe de vos revenus dès leur réception, avant de régler vos dépenses courantes.",
            titleEn: "Pay Yourself First",
            textEn: "The cornerstone of financial freedom: automate saving and investing a fixed portion of your income immediately when received, before spending the rest."
        ),
        KnowledgeFact(
            id: 40,
            category: "Psychologie Financière",
            icon: "xmark.circle.fill",
            titleFr: "Le Biais du Coût Irrécupérable",
            textFr: "Poursuivre un projet ou conserver un mauvais investissement sous prétexte qu'on y a déjà investi du temps ou de l'argent est une illusion. Seule la valeur future doit guider vos décisions.",
            titleEn: "The Sunk Cost Fallacy",
            textEn: "Holding a bad investment because you've already sunk money into it is irrational. Rational decisions depend solely on forward-looking prospects."
        ),
        KnowledgeFact(
            id: 41,
            category: "Économie",
            icon: "shield.lefthalf.filled",
            titleFr: "L'Avantage Compétitif Durable (Moat)",
            textFr: "Popularisé par Warren Buffett, le « moat » (fossé défensif) désigne l'atout unique (marque, réseau, brevets, coûts réduits) qui protège une entreprise contre la concurrence sur le long terme.",
            titleEn: "Economic Moats",
            textEn: "Coined by Warren Buffett: an economic moat is a durable competitive advantage—such as network effects or brand loyalty—that protects pricing power."
        ),
        KnowledgeFact(
            id: 42,
            category: "Finance",
            icon: "chart.bar.xaxis",
            titleFr: "La Diversification (Markowitz)",
            textFr: "Le prix Nobel Harry Markowitz a démontré que combiner des actifs non corrélés permet de réduire considérablement le risque global sans pour autant diminuer l'espérance de rendement.",
            titleEn: "Modern Portfolio Theory",
            textEn: "Nobel laureate Harry Markowitz proved that combining uncorrelated assets significantly lowers portfolio risk without sacrificing expected returns."
        ),
        KnowledgeFact(
            id: 43,
            category: "Économie",
            icon: "arrow.left.arrow.right",
            titleFr: "Le Coût d'Opportunité",
            textFr: "Toute décision financière ou de vie implique un renoncement. Le coût réel de dépenser 1 000 € aujourd'hui n'est pas seulement 1 000 €, mais ce que cette somme aurait produit investie sur 20 ans.",
            titleEn: "Opportunity Cost",
            textEn: "Every choice carries an unseen trade-off: spending $1,000 today costs not just the cash, but what that capital could have generated compounded over 20 years."
        ),
        KnowledgeFact(
            id: 44,
            category: "Richesse",
            icon: "book.fill",
            titleFr: "Le Capital Humain",
            textFr: "Votre compétence la plus rentable au cours des premières décennies de votre vie est votre propre capacité à apprendre et à résoudre des problèmes rares. L'investissement en formation offre le meilleur ROI.",
            titleEn: "Investing in Human Capital",
            textEn: "In your early decades, your most compounding asset is your skill stack. Acquiring scarce, high-value capabilities yields unmatched long-term returns."
        ),
        KnowledgeFact(
            id: 45,
            category: "Psychologie Financière",
            icon: "car.fill",
            titleFr: "Le Paradoxe de l'Homme dans la Voiture",
            textFr: "Morgan Housel remarque que lorsqu'on croise une voiture de luxe, on s'imagine au volant admiré des autres, sans jamais prêter attention au conducteur. La richesse ostentatoire n'achète pas le respect.",
            titleEn: "The Man in the Car Paradox",
            textEn: "Morgan Housel observes: when you see a luxury car, you imagine yourself driving it, rarely admiring the driver. Flashy spending rarely buys respect."
        ),

        // --- 46 to 75: Histoire des Idées & Découvertes Scientifiques ---
        KnowledgeFact(
            id: 46,
            category: "Histoire des Sciences",
            icon: "gearshape.2.fill",
            titleFr: "Le Mécanisme d'Anticythère",
            textFr: "Découvert dans une épave antique en Grèce, ce mécanisme en bronze datant de plus de 2 000 ans calculait avec des dizaines d'engrenages les positions des planètes et les éclipses solaires et lunaires.",
            titleEn: "The Antikythera Mechanism",
            textEn: "Recovered from an ancient shipwreck, this 2,000-year-old geared bronze mechanism accurately computed planetary orbits and eclipse cycles."
        ),
        KnowledgeFact(
            id: 47,
            category: "Histoire",
            icon: "books.vertical.fill",
            titleFr: "La Bibliothèque d'Alexandrie",
            textFr: "Fondée au IIIe siècle avant notre ère, elle visait à rassembler la totalité du savoir universel. Chaque navire accostant au port devait prêter ses livres pour qu'ils soient copiés à la main.",
            titleEn: "The Library of Alexandria",
            textEn: "Founded in the 3rd century BC to gather all human knowledge, arriving ships had their manuscripts seized, transcribed by hand, and cataloged."
        ),
        KnowledgeFact(
            id: 48,
            category: "Sciences",
            icon: "laptopcomputer",
            titleFr: "Ada Lovelace et le premier algorithme",
            textFr: "En 1843, la mathématicienne Ada Lovelace écrivit le premier algorithme destiné à être exécuté par une machine (la machine analytique de Babbage), devenant la pionnière de l'informatique moderne.",
            titleEn: "Ada Lovelace: First Programmer",
            textEn: "In 1843, Ada Lovelace published an algorithm designed for Babbage's Analytical Engine, recognizing that machines could manipulate symbols beyond numbers."
        ),
        KnowledgeFact(
            id: 49,
            category: "Biologie",
            icon: "dna",
            titleFr: "La Double Hélice de l'ADN",
            textFr: "Découverte en 1953 grâce aux travaux photographiques aux rayons X de Rosalind Franklin, la structure en double hélice de l'ADN explique comment le code génétique peut se répliquer à l'identique.",
            titleEn: "The DNA Double Helix",
            textEn: "Illuminated in 1953 by Rosalind Franklin's Photo 51, DNA's double-helix structure revealed the physical mechanism for exact genetic replication."
        ),
        KnowledgeFact(
            id: 50,
            category: "Médecine",
            icon: "cross.vial.fill",
            titleFr: "La Découverte de la Pénicilline",
            textFr: "En 1928, Alexander Fleming remarqua qu'une moisissure (Penicillium notatum) avait accidentellement contaminé une boîte de Pétri et détruit les bactéries environnantes, inaugurant l'ère des antibiotiques.",
            titleEn: "The Accidental Penicillin",
            textEn: "In 1928, Alexander Fleming observed a stray Penicillium mold halo in a petri dish that lysed surrounding staph bacteria, launching the antibiotic era."
        ),
        KnowledgeFact(
            id: 51,
            category: "Sciences",
            icon: "microscope.fill",
            titleFr: "La Théorie Microbienne de Pasteur",
            textFr: "En réfutant la génération spontanée par des flacons à col de cygne, Louis Pasteur a révolutionné l'hygiène, la pasteurisation et sauvé des millions de vies grâce aux vaccins.",
            titleEn: "Pasteur's Germ Theory",
            textEn: "By disproving spontaneous generation with swan-neck flasks, Louis Pasteur established germ theory, transforming surgery, sterilization, and immunology."
        ),
        KnowledgeFact(
            id: 52,
            category: "Sciences",
            icon: "applelogo",
            titleFr: "La Pomme de Newton et l'Unification",
            textFr: "Le génie de Newton ne fut pas de découvrir la gravité, mais d'unifier les lois terrestres et cosmiques : la même force qui fait tomber une pomme maintient la Lune en orbite autour de la Terre.",
            titleEn: "Newtonian Universal Gravitation",
            textEn: "Newton's breakthrough was universal unification: realizing the very same force accelerating an apple to the ground governs planetary orbits in space."
        ),
        KnowledgeFact(
            id: 53,
            category: "Biologie",
            icon: "leaf.arrow.triangle.circlepath",
            titleFr: "La Photosynthèse et l'Oxygène",
            textFr: "Il y a 2,4 milliards d'années, la « Grande Oxydation » provoquée par les cyanobactéries a enrichi notre atmosphère en oxygène, rendant possible l'évolution des organismes multicellulaires.",
            titleEn: "The Great Oxidation Event",
            textEn: "2.4 billion years ago, photosynthetic cyanobacteria saturated the oceans with oxygen, transforming Earth's atmosphere and paving the way for complex life."
        ),
        KnowledgeFact(
            id: 54,
            category: "Philosophie",
            icon: "quote.bubble.fill",
            titleFr: "Le Rasoir d'Ockham",
            textFr: "Face à plusieurs hypothèses concurrentes qui expliquent un même phénomène, la méthode scientifique privilégie l'explication qui introduit le moins de suppositions superflues.",
            titleEn: "Occam's Razor",
            textEn: "When evaluating competing hypotheses, the scientific method favors the explanation making the fewest speculative assumptions."
        ),
        KnowledgeFact(
            id: 55,
            category: "Physique",
            icon: "lightbulb.fill",
            titleFr: "L'Effet Photoélectrique d'Einstein",
            textFr: "Ce n'est pas pour la relativité qu'Albert Einstein a reçu le prix Nobel de physique en 1921, mais pour son explication de l'effet photoélectrique démontrant que la lumière est constituée de quanta (photons).",
            titleEn: "The Photoelectric Quantum Leap",
            textEn: "Einstein won his 1921 Nobel Prize not for relativity, but for showing light delivers energy in discrete quantum packets (photons)."
        ),

        // --- 56 to 100: Mathématiques, Cerveau, Évolution & Clés d'apprentissage ---
        KnowledgeFact(
            id: 56,
            category: "Neurosciences",
            icon: "sparkles",
            titleFr: "La Neuroplasticité Adulte",
            textFr: "Contrairement au dogme du XXe siècle, le cerveau adulte crée de nouvelles connexions synaptiques et de nouveaux neurones (neurogenèse dans l'hippocampe) tout au long de la vie lors de nouveaux apprentissages.",
            titleEn: "Lifelong Neuroplasticity",
            textEn: "Adult brains continually reorganize neural circuits and generate new neurons in the hippocampus in response to novelty and focused training."
        ),
        KnowledgeFact(
            id: 57,
            category: "Mathématiques",
            icon: "number",
            titleFr: "Le Nombre d'Or (Phi ≈ 1,618)",
            textFr: "La suite de Fibonacci (0, 1, 1, 2, 3, 5, 8...) converge vers le nombre d'or. On retrouve cette proportion dans la disposition des graines de tournesol, des pommes de pin et des spirales de coquillages.",
            titleEn: "The Golden Ratio in Nature",
            textEn: "The ratio between consecutive Fibonacci numbers converges to Phi (1.618). Plants use this exact packing angle to maximize sunlight exposure."
        ),
        KnowledgeFact(
            id: 58,
            category: "Productivité",
            icon: "repeat",
            titleFr: "La Répétition Espacée",
            textFr: "Pour ancrer une information dans la mémoire à long terme, il faut la réviser juste au moment où le cerveau s'apprête à l'oublier (courbe de l'oubli d'Ebbinghaus), avec des intervalles exponentiels.",
            titleEn: "Spaced Repetition Systems",
            textEn: "Reviewing material just as retention drops—along Ebbinghaus's forgetting curve—triggers efficient long-term synaptic consolidation."
        ),
        KnowledgeFact(
            id: 59,
            category: "Psychologie",
            icon: "arrow.triangle.merge",
            titleFr: "L'Effet de Récence et de Primauté",
            textFr: "Dans une liste ou une présentation, notre cerveau se souvient principalement des premiers et des derniers éléments. Commencez et terminez toujours par vos arguments les plus percutants.",
            titleEn: "Serial Position Effect",
            textEn: "We naturally recall items at the beginning and end of a list far better than the middle. Structure presentations with peak bookends."
        ),
        KnowledgeFact(
            id: 60,
            category: "Sciences",
            icon: "drop.triangle.fill",
            titleFr: "La Loi de Moore",
            textFr: "Énoncée par Gordon Moore en 1965, elle observait que le nombre de transistors sur une puce électronique double tous les deux ans, alimentant la révolution informatique mondiale.",
            titleEn: "Moore's Law",
            textEn: "Coined in 1965, Moore observed transistor density doubles roughly every two years, driving the exponential drop in computational costs."
        ),
        KnowledgeFact(
            id: 61,
            category: "Économie",
            icon: "scalemass.fill",
            titleFr: "La Loi des Rendements Décroissants",
            textFr: "Au-delà d'un certain seuil, chaque unité d'effort ou de capital supplémentaire produit un gain marginal de plus en plus faible. Savoir s'arrêter évite l'épuisement improductif.",
            titleEn: "Diminishing Marginal Returns",
            textEn: "Past an optimal threshold, additional effort yields progressively smaller gains. Identifying this plateau prevents wasted energy."
        ),
        KnowledgeFact(
            id: 62,
            category: "Biologie",
            icon: "heart.fill",
            titleFr: "Le Cœur Humain",
            textFr: "En une seule vie humaine moyenne, le cœur bat plus de 2,5 à 3 milliards de fois et pompe l'équivalent de 200 millions de litres de sang sans jamais s'arrêter.",
            titleEn: "The Human Heart's Feat",
            textEn: "Over an average lifetime, the human heart beats over 2.5 billion times and pumps enough blood to fill three supertankers without rest."
        ),
        KnowledgeFact(
            id: 63,
            category: "Astronomie",
            icon: "globe.europe.africa.fill",
            titleFr: "L'Atmosphère Terrestre",
            textFr: "Ramenée à l'échelle d'une pomme, l'atmosphère respirable de la Terre est plus fine que la peau du fruit : une mince pellicule fragile qui rend toute vie possible.",
            titleEn: "Earth's Fragile Atmosphere",
            textEn: "Relative to Earth's size, our breathable atmosphere is thinner than the skin of an apple: an exceptionally delicate shield sustaining all life."
        ),
        KnowledgeFact(
            id: 64,
            category: "Productivité",
            icon: "lock.shield.fill",
            titleFr: "Le Deep Work (Travail Profond)",
            textFr: "Cal Newport définit le Deep Work comme la capacité de se concentrer sans distraction sur une tâche cognitivement exigeante : c'est la compétence la plus rare et recherchée de l'économie moderne.",
            titleEn: "Cal Newport's Deep Work",
            textEn: "Deep work—uninterrupted concentration on hard cognitive challenges—is becoming both increasingly rare and economically valuable."
        ),
        KnowledgeFact(
            id: 65,
            category: "Finance",
            icon: "umbrella.fill",
            titleFr: "Le Fonds d'Urgence",
            textFr: "Disposer de 3 à 6 mois de dépenses courantes sur un compte sécurisé et liquide supprime le stress financier et vous évite d'avoir à brader vos investissements en période de crise.",
            titleEn: "Emergency Reserves",
            textEn: "Keeping 3–6 months of basic living expenses liquid eliminates panic during volatility, ensuring you never sell depreciated assets under stress."
        ),
        KnowledgeFact(
            id: 66,
            category: "Sciences",
            icon: "network",
            titleFr: "Le Mycélium : L'Internet des Forêts",
            textFr: "Sous le sol des forêts, les réseaux de champignons (mycélium) relient les racines des arbres entre eux, leur permettant d'échanger des nutriments, du carbone et des signaux d'alerte biochimiques.",
            titleEn: "The Wood Wide Web",
            textEn: "Underground fungal mycelium networks connect tree root systems, transferring nutrients, water, and biochemical warning signals across entire forests."
        ),
        KnowledgeFact(
            id: 67,
            category: "Neurosciences",
            icon: "bed.double.fill",
            titleFr: "Le Sommeil Paradoxal (REM)",
            textFr: "Durant la phase de sommeil paradoxal, le cerveau intègre les apprentissages complexes, consolide la mémoire émotionnelle et associe des concepts lointains pour stimuler la créativité.",
            titleEn: "REM Sleep and Synthesis",
            textEn: "During REM sleep, the brain connects distantly related memories, processing emotional experiences and sparking novel creative breakthroughs."
        ),
        KnowledgeFact(
            id: 68,
            category: "Productivité",
            icon: "flag.checkered",
            titleFr: "L'Effet des Petites Victoires",
            textFr: "Terminer une petite tâche le matin libère de la dopamine, le neurotransmetteur de la motivation, créant une cascade positive qui facilite l'attaque des projets plus lourds.",
            titleEn: "Small Wins and Dopamine",
            textEn: "Completing a concrete small task early triggers dopamine release, building intrinsic momentum that makes tackling larger goals easier."
        ),
        KnowledgeFact(
            id: 69,
            category: "Astronomie",
            icon: "star.fill",
            titleFr: "Les Étoiles Filantes",
            textFr: "La plupart des étoiles filantes sont provoquées par des grains de poussière cosmique pas plus gros qu'un grain de sable qui se consument par friction à plus de 50 km/s dans la haute atmosphère.",
            titleEn: "Shooting Stars",
            textEn: "Most shooting stars are caused by cosmic dust particles smaller than a grain of sand vaporizing at 50+ km/s upon atmospheric entry."
        ),
        KnowledgeFact(
            id: 70,
            category: "Psychologie",
            icon: "arrow.up.right",
            titleFr: "L'État d'Esprit de Développement (Mindset)",
            textFr: "Les recherches de Carol Dweck montrent que considérer l'intelligence comme un muscle qui se développe par l'effort transforme les échecs en occasions d'apprentissage plutôt qu'en jugements.",
            titleEn: "Growth Mindset (Carol Dweck)",
            textEn: "Viewing intelligence as malleable through deliberate practice transforms setbacks from self-doubt triggers into valuable data points."
        ),
        KnowledgeFact(
            id: 71,
            category: "Mathématiques",
            icon: "infinity",
            titleFr: "Il existe plusieurs tailles d'Infinis",
            textFr: "Le mathématicien Georg Cantor a prouvé au XIXe siècle que l'infini des nombres réels est strictement plus grand que l'infini des nombres entiers : il existe des infinis incommensurables.",
            titleEn: "Cantor's Hierarchy of Infinities",
            textEn: "Georg Cantor mathematically proved that the infinity of real numbers is strictly larger than the infinity of integers: infinities have sizes."
        ),
        KnowledgeFact(
            id: 72,
            category: "Physique",
            icon: "circle.grid.2x2.fill",
            titleFr: "L'Intrication Quantique",
            textFr: "Deux particules intriquées restent corrélées instantanément, quelle que soit la distance qui les sépare dans l'univers, ce qu'Einstein appelait avec scepticisme une « action fantomatique à distance ».",
            titleEn: "Quantum Entanglement",
            textEn: "Entangled particles maintain instantaneous quantum state correlation across cosmic distances, prompting Einstein's famous 'spooky action' critique."
        ),
        KnowledgeFact(
            id: 73,
            category: "Productivité",
            icon: "envelope.fill",
            titleFr: "Le Traitement par Lots (Batching)",
            textFr: "Regrouper les tâches similaires (répondre à tous ses e-mails en 2 sessions par jour, traiter l'administratif d'un coup) évite la dispersion mentale et démultiplie la vitesse d'exécution.",
            titleEn: "Task Batching",
            textEn: "Clustering similar administrative tasks into dedicated windows reduces transition latency and preserves sustained uninterrupted focus."
        ),
        KnowledgeFact(
            id: 74,
            category: "Économie",
            icon: "building.2.fill",
            titleFr: "Les Effets de Réseau",
            textFr: "Un produit ou service bénéficie d'un effet de réseau lorsque chaque nouvel utilisateur accroît la valeur de la plateforme pour tous les autres (ex : téléphones, internet, marchés).",
            titleEn: "Network Effects",
            textEn: "A product exhibits network effects when each incremental participant directly increases value for all existing users, creating compounding defensibility."
        ),
        KnowledgeFact(
            id: 75,
            category: "Biologie",
            icon: "eye",
            titleFr: "Le Point Aveugle de l'Œil",
            textFr: "Là où le nerf optique traverse la rétine, il n'y a aucun photorécepteur. Votre cerveau comble en permanence cette tache aveugle en extrapolant les textures et couleurs environnantes.",
            titleEn: "The Eye's Blind Spot",
            textEn: "Where the optic nerve exits the retina, no photoreceptors exist. Your visual cortex seamlessly interpolates surrounding colors to fill the gap."
        ),
        KnowledgeFact(
            id: 76,
            category: "Psychologie",
            icon: "person.2.fill",
            titleFr: "Le Nombre de Dunbar (150)",
            textFr: "L'anthropologue Robin Dunbar a montré que la taille du néocortex humain limite notre capacité à entretenir des relations sociales stables à environ 150 personnes.",
            titleEn: "Dunbar's Number (150)",
            textEn: "Anthropologist Robin Dunbar showed human neocortex architecture limits our capacity to sustain cohesive personal relationships to roughly 150 people."
        ),
        KnowledgeFact(
            id: 77,
            category: "Sciences",
            icon: "circle.dotted",
            titleFr: "L'Atome est composé de 99,9999999% de vide",
            textFr: "Si le noyau d'un atome avait la taille d'une bille de billard au centre d'un terrain de football, ses électrons seraient de minuscules grains de poussière tourbillonnant dans les tribunes.",
            titleEn: "Atomic Emptiness",
            textEn: "If an atomic nucleus were scaled to a golf ball on a soccer pitch, its orbiting electrons would be speck-like particles around the stadium stands."
        ),
        KnowledgeFact(
            id: 78,
            category: "Productivité",
            icon: "list.bullet.clipboard.fill",
            titleFr: "La Check-list d'Aviation",
            textFr: "Même les pilotes et chirurgiens les plus chevronnés utilisent des check-lists rigoureuses : elles libèrent la mémoire de travail et éliminent les erreurs dues à la routine ou à la fatigue.",
            titleEn: "The Power of Checklists",
            textEn: "Aviation and surgical checklists prevent catastrophic oversights by externalizing procedural memory and eliminating reliance on mental recall."
        ),
        KnowledgeFact(
            id: 79,
            category: "Richesse",
            icon: "hands.sparkles.fill",
            titleFr: "La Vraie Définition de la Richesse",
            textFr: "Comme l'écrivait Sénèque : « La richesse ne consiste pas à posséder de grands biens, mais à avoir peu de désirs. » La vraie liberté financière est le contrôle absolu de son temps.",
            titleEn: "The True Nature of Wealth",
            textEn: "Seneca wrote: 'Wealth consists not in having great possessions, but in having few wants.' Ultimate financial freedom is sovereign control over your time."
        ),
        KnowledgeFact(
            id: 80,
            category: "Astronomie",
            icon: "sparkle",
            titleFr: "Les Éclipses Solaires Totales",
            textFr: "Par une coïncidence géométrique extraordinaire, le Soleil est 400 fois plus grand que la Lune mais se trouve 400 fois plus loin, leur donnant exactement la même taille apparente dans notre ciel.",
            titleEn: "The Solar Eclipse Coincidence",
            textEn: "By an astonishing cosmic coincidence, the Sun is 400 times wider than the Moon but also 400 times further away, yielding identical angular diameter."
        ),
        KnowledgeFact(
            id: 81,
            category: "Biologie",
            icon: "figure.walk.motion",
            titleFr: "L'Adaptation Hédonique",
            textFr: "Les êtres humains retournent rapidement à leur niveau de bonheur de base après un événement positif ou négatif. Investir dans des expériences et des relations durables surpasse l'achat d'objets.",
            titleEn: "The Hedonic Treadmill",
            textEn: "Humans rapidly recalibrate to a baseline level of subjective happiness following triumphs or setbacks. Experiences outlast material gains."
        ),
        KnowledgeFact(
            id: 82,
            category: "Sciences",
            icon: "globe.asia.australia.fill",
            titleFr: "La Dérive des Continents (Tectonique)",
            textFr: "Les plaques tectoniques terrestres se déplacent à peu près à la même vitesse que poussent vos ongles (environ 2 à 5 centimètres par an), remodelant continuellement la surface du globe.",
            titleEn: "Plate Tectonics Speed",
            textEn: "Earth's tectonic plates drift at roughly the rate human fingernails grow (~2.5 cm/year), continually shifting continents over geological epochs."
        ),
        KnowledgeFact(
            id: 83,
            category: "Physique",
            icon: "speaker.wave.2.fill",
            titleFr: "La Vitesse du Son",
            textFr: "Le son se propage à environ 340 m/s dans l'air, mais 4 fois plus vite dans l'eau (1 500 m/s) et 15 fois plus vite dans l'acier (5 000 m/s) grâce à la densité atomique des matériaux.",
            titleEn: "The Speed of Sound",
            textEn: "Sound travels at 340 m/s in air, but over 4 times faster in water (1,500 m/s) and 15 times faster in solid steel due to tightly packed molecular bonds."
        ),
        KnowledgeFact(
            id: 84,
            category: "Productivité",
            icon: "arrow.counterclockwise.circle.fill",
            titleFr: "La Rétroaction Rapide (Feedback Loops)",
            textFr: "Plus le délai entre une action et son résultat est court, plus l'apprentissage est rapide. Raccourcir les boucles de rétroaction accélère l'acquisition de n'importe quelle compétence.",
            titleEn: "Rapid Feedback Loops",
            textEn: "The shorter the latency between an attempt and its outcome, the faster neural adaptation occurs. Tightening loops accelerates skill acquisition."
        ),
        KnowledgeFact(
            id: 85,
            category: "Psychologie",
            icon: "questionmark.circle.fill",
            titleFr: "L'Effet Pygmalion",
            textFr: "Des attentes élevées placées en une personne améliorent ses performances réelles de manière mesurable. Croire au potentiel de ses collaborateurs ou enfants influence positivement leurs résultats.",
            titleEn: "The Pygmalion Effect",
            textEn: "High expectations placed upon individuals demonstrably enhance their actual performance through subtle behavioral reinforcement."
        ),
        KnowledgeFact(
            id: 86,
            category: "Neurosciences",
            icon: "cup.and.saucer.fill",
            titleFr: "La Caféine et l'Adénosine",
            textFr: "La caféine ne produit pas d'énergie : elle bloque temporairement les récepteurs cérébraux de l'adénosine, la molécule qui signale la somnolence. Attendre 90 min après le réveil avant le premier café évite le crash.",
            titleEn: "Caffeine and Adenosine",
            textEn: "Caffeine does not generate energy; it antagonizes adenosine sleep receptors. Delaying caffeine 90 minutes after waking avoids afternoon crashes."
        ),
        KnowledgeFact(
            id: 87,
            category: "Économie",
            icon: "creditcard.fill",
            titleFr: "L'Illusion Monétaire",
            textFr: "Considérer l'argent en valeur nominale sans tenir compte de l'inflation est une erreur fréquente. Un rendement de 4% avec 5% d'inflation équivaut en réalité à une perte de pouvoir d'achat de 1%.",
            titleEn: "Money Illusion",
            textEn: "Focusing on nominal currency without adjusting for inflation is deceptive: earning 4% while inflation runs at 5% is a net real loss in purchasing power."
        ),
        KnowledgeFact(
            id: 88,
            category: "Sciences",
            icon: "tree.fill",
            titleFr: "L'Âge des Arbres Vénérables",
            textFr: "Le pin Bristlecone « Mathusalem », situé dans les montagnes Blanches en Californie, est âgé de plus de 4 850 ans : il germait déjà lors de la construction des premières pyramides d'Égypte.",
            titleEn: "Ancient Bristlecone Pines",
            textEn: "California's 'Methuselah' bristlecone pine is over 4,850 years old—already a living sapling when the Great Pyramid of Giza was being constructed."
        ),
        KnowledgeFact(
            id: 89,
            category: "Physique",
            icon: "prism",
            titleFr: "La Décomposition de la Lumière",
            textFr: "En 1666, Isaac Newton fit passer un rayon de lumière blanche à travers un prisme pour prouver que les couleurs de l'arc-en-ciel sont des composantes intrinsèques de la lumière, et non créées par le verre.",
            titleEn: "Newton's Prism Experiment",
            textEn: "In 1666, Isaac Newton refracted white light through a glass prism, proving that spectral colors are intrinsic components of light, not glass artifacts."
        ),
        KnowledgeFact(
            id: 90,
            category: "Productivité",
            icon: "arrow.triangle.pull",
            titleFr: "La Règle des 80% (Hara Hachi Bu)",
            textFr: "Pratique ancestrale d'Okinawa (région aux nombreux centenaires) : cesser de manger lorsque l'estomac est rempli à 80%. Cette règle s'applique aussi aux journées de travail pour éviter le surmenage.",
            titleEn: "Hara Hachi Bu (80% Rule)",
            textEn: "Okinawa's centenarian practice: stop eating when 80% full. Applied to work schedules, leaving 20% margin prevents cognitive burnout."
        ),
        KnowledgeFact(
            id: 91,
            category: "Biologie",
            icon: "person.text.rectangle",
            titleFr: "Le Microbiote Intestinal",
            textFr: "Nos intestins abritent plus de 30 000 milliards de bactéries qui produisent environ 90% de la sérotonine de notre organisme, jouant un rôle direct sur notre humeur et notre système immunitaire.",
            titleEn: "The Gut-Brain Axis",
            textEn: "Our gut microbiome houses 30+ trillion bacteria producing ~90% of the body's serotonin, directly modulating immune response and mental well-being."
        ),
        KnowledgeFact(
            id: 92,
            category: "Psychologie",
            icon: "slider.horizontal.3",
            titleFr: "L'Effet d'Ancrage",
            textFr: "La première information chiffrée entendue lors d'une négociation sert de point d'ancrage psychologique disproportionné pour toutes les estimations ultérieures.",
            titleEn: "The Anchoring Bias",
            textEn: "The first numeric figure introduced in negotiations unconsciously anchors subsequent bids, warping rational valuation."
        ),
        KnowledgeFact(
            id: 93,
            category: "Astronomie",
            icon: "record.circle",
            titleFr: "Jupiter l'Aspirateur du Système Solaire",
            textFr: "Grâce à son immense champ gravitationnel, Jupiter capture ou dévie la majorité des comètes et astéroïdes dangereux, protégeant ainsi la Terre d'impacts catastrophiques réguliers.",
            titleEn: "Jupiter the Cosmic Shield",
            textEn: "Jupiter's colossal gravity acts as a planetary vacuum cleaner, absorbing or deflecting rogue comets that would otherwise endanger inner terrestrial planets."
        ),
        KnowledgeFact(
            id: 94,
            category: "Productivité",
            icon: "clock.badge.checkmark",
            titleFr: "La Technique Pomodoro",
            textFr: "Travailler 25 minutes avec un engagement absolu suivi de 5 minutes de déconnexion totale permet de préserver la fraîcheur mentale sur toute une journée sans baisse de régime.",
            titleEn: "The Pomodoro Method",
            textEn: "Working in 25-minute sprints followed by strict 5-minute cognitive rests sustains mental sharpness across long workdays."
        ),
        KnowledgeFact(
            id: 95,
            category: "Sciences",
            icon: "snow",
            titleFr: "L'Unicité des Flocons de Neige",
            textFr: "Chaque flocon de neige suit une trajectoire microscopique unique de température et d'humidité en tombant, donnant naissance à des géométries cristallines hexagonales jamais identiques.",
            titleEn: "Snowflake Morphology",
            textEn: "Because each snowflake navigates unique micro-variations in atmospheric temperature and moisture, no two complex crystals share the exact same geometry."
        ),
        KnowledgeFact(
            id: 96,
            category: "Richesse",
            icon: "scalemass",
            titleFr: "Le Ratio Dépenses / Liberté",
            textFr: "Le moyen le plus rapide d'atteindre l'indépendance financière n'est pas seulement d'augmenter ses revenus, mais de maintenir un train de vie sobre pour maximiser son taux d'épargne.",
            titleEn: "Lifestyle Inflation Defense",
            textEn: "The fastest road to financial freedom is keeping fixed living expenses modest while income climbs, maximizing the savings rate for compounding."
        ),
        KnowledgeFact(
            id: 97,
            category: "Histoire",
            icon: "scroll.fill",
            titleFr: "La Pierre de Rosette",
            textFr: "Découverte en 1799 avec le même décret gravé en trois écritures (hiéroglyphes, démotique et grec ancien), elle permit à Jean-François Champollion de déchiffrer les hiéroglyphes égyptiens en 1822.",
            titleEn: "The Rosetta Stone",
            textEn: "Carved with a single bilingual decree in three scripts in 196 BC, it unlocked Egyptian hieroglyphs for Jean-François Champollion in 1822."
        ),
        KnowledgeFact(
            id: 98,
            category: "Physique",
            icon: "atom",
            titleFr: "L'Énergie de Masse E = mc²",
            textFr: "La matière est une forme d'énergie extraordinairement concentrée. La masse d'un seul trombone métallique renferme autant d'énergie potentielle qu'une bombe de 20 kilotonnes.",
            titleEn: "Mass-Energy Equivalence",
            textEn: "Because c² is an astronomically large number (9 x 10¹⁶ m²/s²), the mass contained within a single steel paperclip holds immense latent energy."
        ),
        KnowledgeFact(
            id: 99,
            category: "Psychologie",
            icon: "heart.text.square.fill",
            titleFr: "La Gratitude Quotidienne",
            textFr: "Noter chaque soir 3 choses pour lesquelles on est reconnaissant reconfigure progressivement les circuits neuronaux de l'attention pour repérer les opportunités plutôt que les menaces.",
            titleEn: "The Gratitude Circuit",
            textEn: "Daily gratitude journaling primes reticular activating systems to identify constructive opportunities instead of dwelling on ambient friction."
        ),
        KnowledgeFact(
            id: 100,
            category: "Sagesse & Sciences",
            icon: "graduationcap.fill",
            titleFr: "L'Effet Feynman d'Apprentissage",
            textFr: "Le prix Nobel Richard Feynman affirmait : « Si vous ne pouvez pas expliquer un concept simplement à un enfant de 10 ans, c'est que vous ne l'avez pas véritablement compris. » La simplification est la preuve ultime de la maîtrise.",
            titleEn: "The Feynman Technique",
            textEn: "Nobel laureate Richard Feynman asserted: 'If you cannot explain a concept simply to a child, you don't truly understand it.' Simplicity is the hallmark of true mastery."
        )
    ]
    
    func randomFact(for lang: LangCode) -> KnowledgeFact {
        let chosen = facts.randomElement() ?? facts[0]
        recordFactShown(chosen.id)
        return chosen
    }
    
    func recordFactShown(_ id: Int) {
        DispatchQueue.main.async {
            var updated = self.recentFactIds.filter { $0 != id }
            updated.insert(id, at: 0)
            if updated.count > 5 {
                updated = Array(updated.prefix(5))
            }
            self.recentFactIds = updated
            UserDefaults.standard.set(updated, forKey: self.recentFactsKey)
        }
    }
    
    var recentFacts: [KnowledgeFact] {
        let byId = Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })
        let resolved = recentFactIds.compactMap { byId[$0] }
        if !resolved.isEmpty {
            return resolved
        }
        return Array(facts.prefix(5))
    }
}

