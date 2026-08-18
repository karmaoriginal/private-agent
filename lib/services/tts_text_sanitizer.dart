/// Prepares assistant text for text-to-speech:
/// - strips markdown formatting (**, *, `, #, links, fences)
/// - replaces emojis with their spoken name ("😂" -> "cara de risa")
/// - collapses whitespace so the engine doesn't pause oddly
class TtsTextSanitizer {
  /// Common emoji -> spoken Spanish name. Unknown emojis become "emoji".
  static const Map<String, String> _emojiNames = {
    '😀': 'cara sonriente', '😃': 'cara sonriente con ojos grandes',
    '😄': 'cara muy sonriente', '😁': 'cara radiante',
    '😆': 'cara riéndose con ojos cerrados', '😅': 'risa con sudor frío',
    '😂': 'cara llorando de risa', '🤣': 'cara revolcándose de risa',
    '😊': 'cara feliz sonrojada', '😇': 'cara con halo',
    '🙂': 'cara ligeramente sonriente', '🙃': 'cara al revés',
    '😉': 'cara guiñando', '😌': 'cara aliviada',
    '😍': 'cara con ojos de corazón', '🥰': 'cara sonriente con corazones',
    '😘': 'cara lanzando un beso', '😋': 'cara saboreando',
    '😜': 'cara sacando la lengua y guiñando', '🤪': 'cara de loco',
    '🤔': 'cara pensativa', '🤨': 'cara con ceja levantada',
    '😐': 'cara neutral', '😑': 'cara sin expresión',
    '😶': 'cara sin boca', '🙄': 'cara con ojos en blanco',
    '😏': 'cara con sonrisa pícara', '😬': 'cara haciendo una mueca',
    '🤐': 'cara con boca de cremallera', '🤫': 'cara pidiendo silencio',
    '🤥': 'cara de mentiroso', '😴': 'cara durmiendo',
    '😪': 'cara de sueño', '😷': 'cara con mascarilla',
    '🤒': 'cara con termómetro', '🤕': 'cara con la cabeza vendada',
    '🤢': 'cara de náuseas', '🤮': 'cara vomitando',
    '🥵': 'cara con calor', '🥶': 'cara con frío',
    '😎': 'cara con gafas de sol', '🤓': 'cara de empollón',
    '🧐': 'cara con monóculo', '😢': 'cara llorando',
    '😭': 'cara llorando fuerte', '😤': 'cara resoplando',
    '😠': 'cara enfadada', '😡': 'cara muy enfadada',
    '🤬': 'cara con símbolos en la boca', '🤯': 'cabeza explotando',
    '😳': 'cara sonrojada', '🥺': 'cara de ojos suplicantes',
    '😱': 'cara gritando de miedo', '😨': 'cara asustada',
    '😰': 'cara ansiosa con sudor', '😥': 'cara triste pero aliviada',
    '😓': 'cara con sudor frío', '🤗': 'cara abrazando',
    '🫡': 'cara saludando', '🤭': 'cara con mano en la boca',
    '🫢': 'cara con ojos abiertos y mano en la boca',
    '💀': 'calavera', '☠️': 'calavera y tibias cruzadas',
    '👻': 'fantasma', '👽': 'alienígena', '🤖': 'robot',
    '😺': 'gato sonriente', '🙈': 'mono que no ve',
    '🙉': 'mono que no oye', '🙊': 'mono que no habla',
    '💩': 'caca', '👍': 'pulgar arriba', '👎': 'pulgar abajo',
    '👌': 'señal de vale', '✌️': 'señal de victoria',
    '🤞': 'dedos cruzados', '🤟': 'gesto de te quiero',
    '🤘': 'cuernos', '👏': 'aplausos', '🙌': 'manos arriba',
    '👐': 'manos abiertas', '🤝': 'apretón de manos',
    '💪': 'bíceps flexionado', '🙏': 'manos juntas',
    '✍️': 'mano escribiendo', '🖐️': 'mano abierta',
    '👋': 'mano saludando', '🤙': 'mano de llámame',
    '💯': 'cien puntos', '🔥': 'fuego', '✨': 'destellos',
    '🎉': 'confeti de fiesta', '🎊': 'bola de confeti',
    '🎈': 'globo', '🎁': 'regalo', '🏆': 'trofeo',
    '🥇': 'medalla de oro', '🥈': 'medalla de plata',
    '🥉': 'medalla de bronce', '⭐': 'estrella', '🌟': 'estrella brillante',
    '💫': 'estrella fugaz', '⚽': 'balón de fútbol',
    '🏀': 'balón de baloncesto', '🎮': 'mando de videojuego',
    '🎲': 'dado', '🎯': 'diana', '🎸': 'guitarra',
    '🎤': 'micrófono', '🎧': 'auriculares', '🎬': 'claqueta',
    '🎨': 'paleta de artista', '❤️': 'corazón rojo',
    '🧡': 'corazón naranja', '💛': 'corazón amarillo',
    '💚': 'corazón verde', '💙': 'corazón azul',
    '💜': 'corazón morado', '🖤': 'corazón negro',
    '🤍': 'corazón blanco', '🤎': 'corazón marrón',
    '💔': 'corazón roto', '💕': 'dos corazones',
    '💖': 'corazón brillante', '💗': 'corazón creciente',
    '💘': 'corazón con flecha', '💝': 'corazón con lazo',
    '💤': 'símbolo de sueño', '💢': 'símbolo de enfado',
    '💬': 'bocadillo de diálogo', '💭': 'bocadillo de pensamiento',
    '🕳️': 'agujero', '👁️': 'ojo', '👀': 'ojos',
    '🧠': 'cerebro', '🦷': 'diente', '🦴': 'hueso',
    '🚀': 'cohete', '✈️': 'avión', '🚁': 'helicóptero',
    '🚗': 'coche', '🚕': 'taxi', '🚌': 'autobús',
    '🏎️': 'coche de carreras', '🚓': 'coche de policía',
    '🚑': 'ambulancia', '🚒': 'camión de bomberos',
    '🚲': 'bicicleta', '🛵': 'scooter', '⛵': 'velero',
    '🚢': 'barco', '⚓': 'ancla', '🗺️': 'mapa del mundo',
    '🌍': 'globo Europa y África', '🌎': 'globo América',
    '🌏': 'globo Asia y Australia', '🏔️': 'montaña nevada',
    '🌋': 'volcán', '🏖️': 'playa', '🏜️': 'desierto',
    '🏝️': 'isla desierta', '🏠': 'casa', '🏢': 'edificio de oficinas',
    '🏥': 'hospital', '🏦': 'banco', '🏨': 'hotel',
    '🏫': 'escuela', '⛪': 'iglesia', '🕌': 'mezquita',
    '🌅': 'amanecer', '🌄': 'amanecer en montañas',
    '🌇': 'atardecer en la ciudad', '🌆': 'ciudad al atardecer',
    '🌃': 'noche estrellada', '🌉': 'puente de noche',
    '🌌': 'vía láctea', '🌈': 'arcoíris', '☀️': 'sol',
    '🌤️': 'sol con nube pequeña', '⛅': 'sol tras una nube',
    '☁️': 'nube', '🌧️': 'nube con lluvia', '⛈️': 'nube con tormenta',
    '🌩️': 'nube con rayo', '🌨️': 'nube con nieve',
    '❄️': 'copo de nieve', '⛄': 'muñeco de nieve',
    '🌪️': 'tornado', '🌫️': 'niebla', '☔': 'paraguas con lluvia',
    '⚡': 'alto voltaje', '💧': 'gota', '🌊': 'ola',
    '📱': 'teléfono móvil', '💻': 'ordenador portátil',
    '⌨️': 'teclado', '🖥️': 'ordenador de sobremesa',
    '🖨️': 'impresora', '🖱️': 'ratón', '💾': 'disquete',
    '💿': 'disco óptico', '📷': 'cámara', '📸': 'cámara con flash',
    '📹': 'videocámara', '🎥': 'cámara de cine',
    '📞': 'auricular de teléfono', '☎️': 'teléfono',
    '📺': 'televisión', '📻': 'radio', '🎙️': 'micrófono de estudio',
    '⏰': 'despertador', '⌛': 'reloj de arena', '⏳': 'reloj de arena corriendo',
    '⌚': 'reloj', '📡': 'antena parabólica', '🔋': 'batería',
    '🔌': 'enchufe', '💡': 'bombilla', '🔦': 'linterna',
    '🕯️': 'vela', '💸': 'dinero con alas', '💵': 'billete de dólar',
    '💰': 'bolsa de dinero', '💳': 'tarjeta de crédito',
    '💎': 'gema', '⚖️': 'balanza', '🔧': 'llave inglesa',
    '🔨': 'martillo', '🛠️': 'martillo y llave', '⛏️': 'pico',
    '🔩': 'tuerca y tornillo', '⚙️': 'engranaje', '🧱': 'ladrillo',
    '🔫': 'pistola de agua', '💣': 'bomba', '🔪': 'cuchillo de cocina',
    '🗡️': 'daga', '⚔️': 'espadas cruzadas', '🛡️': 'escudo',
    '🔮': 'bola de cristal', '📿': 'rosario', '💈': 'poste de barbero',
    '⚗️': 'alambique', '🔭': 'telescopio', '🔬': 'microscopio',
    '🩺': 'estetoscopio', '💊': 'píldora', '💉': 'jeringuilla',
    '🧬': 'ADN', '🦠': 'microbio', '🧪': 'tubo de ensayo',
    '🌡️': 'termómetro', '🧹': 'escoba', '🧻': 'rollo de papel',
    '🚽': 'inodoro', '🚿': 'ducha', '🛁': 'bañera',
    '🧼': 'jabón', '🧽': 'esponja', '🔑': 'llave',
    '🗝️': 'llave antigua', '🚪': 'puerta', '🪑': 'silla',
    '🛋️': 'sofá', '🛏️': 'cama', '🧸': 'oso de peluche',
    '🖼️': 'cuadro enmarcado', '🛍️': 'bolsas de compra',
    '🛒': 'carrito de compra', '📦': 'paquete', '📫': 'buzón',
    '✉️': 'sobre', '📧': 'correo electrónico', '💌': 'carta de amor',
    '📥': 'bandeja de entrada', '📤': 'bandeja de salida',
    '📜': 'pergamino', '📃': 'página', '📄': 'documento',
    '📊': 'gráfico de barras', '📈': 'gráfico ascendente',
    '📉': 'gráfico descendente', '🗒️': 'bloc de notas',
    '📅': 'calendario', '📆': 'calendario de hojas',
    '🗑️': 'papelera', '📇': 'tarjetero', '📋': 'portapapeles',
    '📁': 'carpeta', '📂': 'carpeta abierta', '🗞️': 'periódico enrollado',
    '📰': 'periódico', '📓': 'cuaderno', '📔': 'cuaderno con tapa',
    '📕': 'libro rojo', '📗': 'libro verde', '📘': 'libro azul',
    '📙': 'libro naranja', '📚': 'libros', '📖': 'libro abierto',
    '🔖': 'marcador', '🧷': 'imperdible', '🔗': 'enlace',
    '📎': 'clip', '🖇️': 'clips unidos', '📐': 'escuadra',
    '📏': 'regla', '🧮': 'ábaco', '📌': 'chincheta',
    '📍': 'chincheta redonda', '✂️': 'tijeras', '🖊️': 'bolígrafo',
    '🖋️': 'pluma estilográfica', '✒️': 'pluma negra',
    '🖌️': 'pincel', '🖍️': 'crayón', '📝': 'nota',
    '✏️': 'lápiz', '🔍': 'lupa a la izquierda',
    '🔎': 'lupa a la derecha', '🔏': 'candado con pluma',
    '🔐': 'candado cerrado con llave', '🔒': 'candado cerrado',
    '🔓': 'candado abierto', '🍎': 'manzana roja',
    '🍊': 'naranja', '🍋': 'limón', '🍉': 'sandía',
    '🍇': 'uvas', '🍓': 'fresa', '🫐': 'arándanos',
    '🍑': 'melocotón', '🥭': 'mango', '🍍': 'piña',
    '🍌': 'plátano', '🥑': 'aguacate', '🍅': 'tomate',
    '🥕': 'zanahoria', '🌽': 'maíz', '🌶️': 'chile picante',
    '🍔': 'hamburguesa', '🍟': 'patatas fritas', '🍕': 'pizza',
    '🌭': 'perrito caliente', '🍿': 'palomitas', '🍩': 'donut',
    '🍪': 'galleta', '🎂': 'tarta de cumpleaños', '🍰': 'tarta',
    '🧁': 'magdalena', '🍫': 'chocolate', '🍬': 'caramelo',
    '🍭': 'piruleta', '🍦': 'helado', '☕': 'café',
    '🍵': 'té', '🧃': 'zumo en brick', '🥤': 'vaso con pajita',
    '🍺': 'cerveza', '🍻': 'brindis con cervezas',
    '🥂': 'brindis con copas', '🍷': 'cop de vino',
    '🥃': 'vaso de whisky', '🍸': 'cóctel', '🍹': 'bebida tropical',
    '🐶': 'perro', '🐱': 'gato', '🐭': 'ratón', '🐹': 'hámster',
    '🐰': 'conejo', '🦊': 'zorro', '🐻': 'oso', '🐼': 'panda',
    '🐨': 'koala', '🐯': 'tigre', '🦁': 'león', '🐮': 'vaca',
    '🐷': 'cerdo', '🐸': 'rana', '🐵': 'mono', '🐔': 'gallina',
    '🐧': 'pingüino', '🐦': 'pájaro', '🦆': 'pato',
    '🦅': 'águila', '🦉': 'búho', '🦇': 'murciélago',
    '🐺': 'lobo', '🐗': 'jabalí', '🐴': 'caballo',
    '🦄': 'unicornio', '🐝': 'abeja', '🐛': 'oruga',
    '🦋': 'mariposa', '🐌': 'caracol', '🐞': 'mariquita',
    '🐜': 'hormiga', '🕷️': 'araña', '🐢': 'tortuga',
    '🐍': 'serpiente', '🦎': 'lagarto', '🐙': 'pulpo',
    '🦑': 'calamar', '🦐': 'camarón', '🦀': 'cangrejo',
    '🐡': 'pez globo', '🐠': 'pez tropical', '🐟': 'pez',
    '🐬': 'delfín', '🐳': 'ballena', '🦈': 'tiburón',
    '🐊': 'cocodrilo', '🌸': 'flor de cerezo', '🌼': 'flor',
    '🌷': 'tulipán', '🌹': 'rosa', '🥀': 'flor marchita',
    '🌺': 'hibisco', '🌻': 'girasol', '🍀': 'trébol de cuatro hojas',
    '🍁': 'hoja de arce', '🍂': 'hoja caída', '🍃': 'hojas al viento',
    '🌵': 'cactus', '🌴': 'palmera', '🌲': 'pino',
    '🌳': 'árbol', '🎄': 'árbol de navidad', '🎃': 'calabaza de halloween',
    '🎅': 'papá noel', '🤶': 'mamá noel', '🧑': 'persona',
    '👶': 'bebé', '👧': 'niña', '👦': 'niño', '👩': 'mujer',
    '👨': 'hombre', '👵': 'abuela', '👴': 'abuelo',
    '👮': 'policía', '🕵️': 'detective', '💂': 'guardia',
    '👷': 'obrero', '🤴': 'príncipe', '👸': 'princesa',
    '👼': 'bebé ángel', '🦸': 'superhéroe', '🦹': 'supervillano',
    '🧙': 'mago', '🧚': 'hada', '🧛': 'vampiro',
    '🧜': 'sirena', '🧝': 'elfo', '🧞': 'genio', '🧟': 'zombi',
    '🏃': 'persona corriendo', '🚶': 'persona caminando',
    '💃': 'mujer bailando', '🕺': 'hombre bailando',
    '🧘': 'persona meditando', '🏄': 'persona haciendo surf',
    '🏊': 'persona nadando', '🚴': 'persona en bicicleta',
    '⛹️': 'persona botando un balón', '🏋️': 'persona levantando pesas',
    '🤸': 'persona haciendo voltereta', '🤺': 'persona esgrimiendo',
    '🤾': 'persona jugando al balonmano', '🏌️': 'persona jugando al golf',
    '🏇': 'carrera de caballos', '🧗': 'persona escalando',
    '🚵': 'persona en bici de montaña', '🤽': 'persona jugando al waterpolo',
    '🛀': 'persona en la bañera', '👫': 'pareja de la mano',
    '💏': 'beso', '💑': 'pareja con corazón', '👪': 'familia',
    '🗣️': 'cabeza hablando', '👤': 'silueta', '👥': 'siluetas',
    '🫂': 'personas abrazándose', '👣': 'huellas',
  };

  /// Emoji pattern: pictographs, symbols, dingbats + variation selector /
  /// ZWJ sequences and skin-tone modifiers.
  static final RegExp _emojiPattern = RegExp(
    '[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
    '\u{FE0F}\u{200D}\u{1F3FB}-\u{1F3FF}\u{2190}-\u{21FF}'
    '\u{2300}-\u{23FF}]+',
    unicode: true,
  );

  /// Converts a full markdown-ish assistant message into plain,
  /// speakable prose.
  static String sanitize(String input) {
    var text = input;

    // Fenced code blocks -> keep the code, drop the fences/language tag
    text = text.replaceAllMapped(
      RegExp(r'```[a-zA-Z]*\n?([\s\S]*?)```'),
      (m) => ' código: ${m.group(1)?.trim() ?? ''} ',
    );
    // Inline code
    text = text.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1) ?? '');
    // Bold / italic (**, __, *, _) -> keep inner text
    text = text.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'__([^_]+)__'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\*([^*\n]+)\*'),
      (m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'_([^_\n]+)_'),
      (m) => m.group(1) ?? '',
    );
    // Strikethrough
    text = text.replaceAllMapped(
      RegExp(r'~~([^~]+)~~'),
      (m) => m.group(1) ?? '',
    );
    // Links [text](url) -> text
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\([^)]*\)'),
      (m) => m.group(1) ?? '',
    );
    // Images ![alt](url) -> "imagen: alt"
    text = text.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
      (m) => ' imagen: ${m.group(1) ?? ''} ',
    );
    // Headings
    text = text.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
    // Blockquotes
    text = text.replaceAll(RegExp(r'^>\s?', multiLine: true), '');
    // Bullet markers at line start -> pause
    text = text.replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), ', ');
    // Numbered list markers
    text = text.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), ', ');
    // Horizontal rules
    text = text.replaceAll(RegExp(r'^\s*(-{3,}|\*{3,})\s*$', multiLine: true), ' ');

    // Emojis -> spoken names
    text = text.replaceAllMapped(_emojiPattern, (m) {
      final raw = m.group(0)!;
      if (raw.trim().isEmpty) return raw;
      // Try full-sequence match first, then char by char.
      final full = _emojiNames[raw];
      if (full != null) return ' $full ';
      final buffer = StringBuffer(' ');
      var current = StringBuffer();
      for (final rune in raw.runes) {
        final char = String.fromCharCode(rune);
        // Skip joiners / variation selectors / skin tones
        if (rune == 0x200D || rune == 0xFE0F || (rune >= 0x1F3FB && rune <= 0x1F3FF)) {
          continue;
        }
        current.write(char);
        final name = _emojiNames[current.toString()];
        if (name != null) {
          buffer.write('$name, ');
          current = StringBuffer();
        }
      }
      if (current.isNotEmpty) buffer.write('emoji, ');
      return buffer.toString();
    });

    // Collapse whitespace
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{2,}'), '. ');
    text = text.replaceAll('\n', ' ');

    return text.trim();
  }
}
