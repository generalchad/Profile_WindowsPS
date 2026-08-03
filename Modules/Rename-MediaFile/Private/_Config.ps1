# =====================================================================
# _Config.ps1 - Shared regex library and lookup tables
#
# Loaded FIRST by the module loader. Every value here is script-scoped
# so private functions can read them without parameter threading.
# =====================================================================

# ---------------------------------------------------------------------
# EPISODE / SEASON PATTERNS
# ---------------------------------------------------------------------

# Scenario 1: Inline show name (e.g. Show.Name.S01E01.Title)
$script:RegexScenario1 = '^(?<Show>.*?)[._\s]+[sS](?<Season>\d+)[eExX](?<Episode>\d+)(?:[._\s-]+(?<Title>.*?))?$|^(?<Show>.*?)[._\s]+(?<Season>\d+)x(?<Episode>\d+)(?:[._\s-]+(?<Title>.*?))?$'

# Scenario 1.5: Standalone season/episode notation (e.g. S01 E01, 1x01) usually found inside organized folders
$script:RegexStandalone = '^[sS]?(?<Season>\d+)[\s._-]*[eExX](?<Episode>\d+)(?:[\s._-]+(?<Title>.*?))?$'

# Scenario 2: Textual episode numbers ("Episode Three")
$script:RegexWordEpisode = '^(?:Episode|Ep)[\s._-]+(?<Word>\w+)(?:[._\s-]+(?<Title>.*?))?$'

# Any explicit episode marker anywhere in a name. Used by the classifier as a hard TV signal.
$script:RegexEpisodeMarker = '(?i)(?:\bs\d{1,2}[\s._-]*e\d{1,3}\b|\b\d{1,2}x\d{2}\b|\bseason[\s._-]*\d{1,2}[\s._-]*episode[\s._-]*\d{1,3}\b|\b(?:19|20)\d{2}[.\-]\d{2}[.\-]\d{2}\b)'

# Matches parent directories containing series/season info, extracting the preceeding Show name
$script:RegexSeasonDir = '^(?<Show>.*?)[._\s-]*(?:[sS]eason|[sS]taffel|[sS]erie[sn]?|[sS])[\s._-]*0*(?<Season>\d+)(?<Trailer>(?:[._\s-].*)?)$'

# Detects a box-set / complete-collection folder holding several seasons (e.g. "Complete Series 1 2 3 4 5")
$script:RegexBoxSet = '(?i)\b(?:complete|full|all)\b[\s._-]*(?:the[\s._-]*)?(?:series|seasons?|collection|box[\s._-]*set|staffeln)?\b'

# Two or more bare numbers in a row, e.g. "1 2 3 4 5" -> multi-season compilation
$script:RegexMultiSeasonNumbers = '\b\d{1,2}(?:[\s._-]+\d{1,2}){1,}\b'

# Detects bonus/extra edge cases, including common misspellings (e.g., outake, bloopers)
$script:RegexExtrasKeywords = '(?i)\b(?:extra[s]?|bonus(?:es)?|outt?ake[s]?|blooper[s]?|gag[s]?|bts|behind.*?scene[s]?|deleted|interview[s]?|featurette[s]?|special[s]?|trailer[s]?|promo[s]?|doc(?:umentary)?(?:ies)?)\b'

# Standalone 4 digit release year (1900-2099)
$script:RegexYear = '(?<!\d)(?<Year>19\d{2}|20\d{2})(?!\d)'

# "Part 2", "Vol 3", "Volume 3", "Chapter 4"
$script:RegexPartVol = '(?i)\b(?:part|pt|vol(?:ume)?|chapter|cd|disc|disk)[\s._-]*(?:\d{1,2}|[ivx]{1,4})\b'

# Anime style absolute numbering: "Show Name - 012" / "[Group] Show 012"
$script:RegexAbsoluteNumber = '(?i)(?:^|[\s._-])-[\s._-]*\d{1,4}(?:[\s._-]|$)|(?:^|[\s._-])[eE][pP]?[\s._-]*\d{1,4}(?:[\s._-]|$)'

# ---------------------------------------------------------------------
# SCENE JUNK
# Kept as a single alternation so it can be applied with -replace
# anywhere inside a candidate title.
# ---------------------------------------------------------------------
$script:JunkTokens = @(
    # Resolution / picture
    '2160p', '1440p', '1080p', '1080i', '720p', '576p', '540p', '480p', '360p', '4k', 'uhd', 'fhd', 'hd', 'sd'
    'hdr10\+?', 'hdr', 'dolby[\s._-]*vision', 'dovi', '10bit', '8bit', 'hi10p?', 'imax'
    # Source
    'bluray', 'blu[\s._-]*ray', 'bdremux', 'bd[\s._-]*rip', 'bdrip', 'brrip', 'br[\s._-]*rip'
    'dvdrip', 'dvd[\s._-]*rip', 'dvdscr', 'dvd[\s._-]*r', 'dvd\d?', 'ntsc', 'pal'
    'web[\s._-]*dl', 'webdl', 'webrip', 'web[\s._-]*rip', 'web', 'hdtv', 'pdtv', 'dsr', 'hdrip', 'hd[\s._-]*rip'
    'remux', 'camrip', 'cam', 'telesync', 'telecine', 'tvrip', 'satrip', 'workprint', 'r5', 'r6'
    # Codec
    'x264', 'x265', 'h[\s._.-]*264', 'h[\s._.-]*265', 'hevc', 'avc', 'xvid', 'divx', 'mpeg[\s._-]*[24]', 'vp9', 'av1'
    # Audio
    'dts[\s._-]*hd(?:[\s._-]*ma)?', 'dts[\s._-]*x', 'dts', 'truehd', 'atmos', 'ddp?[\s._-]*?[57][\s._.-]1'
    'e?ac[\s._-]*3', 'aac2?(?:[\s._.-]0)?', 'aac', 'mp3', 'flac', 'opus', 'pcm', 'lpcm'
    '[257][\s._.-]1(?:ch)?', '2[\s._.-]0(?:ch)?', 'dual[\s._-]*audio', 'dubbed', 'subbed', 'subs', 'multi[\s._-]*sub'
    # Release / edition markers
    'proper', 'repack', 'rerip', 'internal', 'limited', 'readnfo', 'nfofix', 'multi'
    'unrated', 'uncut', 'uncensored', 'extended', 'remastered', 'restored', 'theatrical', 'directors?[\s._-]*cut'
    'retail', 'custom', 'complete', 'untouched'
)
$script:RegexSceneJunk = '(?i)\b(?:' + ($script:JunkTokens -join '|') + ')\b'

# Bracketed groups: non greedy so multiple bracket sets are handled independently.
$script:RegexBracketed = '\([^)]*\)|\[[^\]]*\]|\{[^}]*\}'

$script:WordMap = @{ 'one'='01'; 'two'='02'; 'three'='03'; 'four'='04'; 'five'='05'; 'six'='06'; 'seven'='07'; 'eight'='08'; 'nine'='09'; 'ten'='10' }

# Official Plex / Jellyfin Local Extras Folder Mapping Table
$script:ExtrasDirMap = [ordered]@{
    '(?i)(?:outt?ake|blooper|gag|bts|behind.*?scene|b-roll)' = 'Behind The Scenes'
    '(?i)(?:delete|cut.*?scene)'                           = 'Deleted Scenes'
    '(?i)(?:interview|cast.*?comment)'                     = 'Interviews'
    '(?i)(?:trailer|promo|teaser)'                         = 'Trailers'
    '(?i)(?:doc|documentary|extra|bonus|feature|misc|special.*feature)' = 'Extras'
}

# =====================================================================
# SUBTITLE SUPPORT
# =====================================================================

# Folder names that commonly hold subtitle sidecars alongside a film.
$script:SubtitleFolderNames = @('subs', 'subtitles', 'subtitle', 'sub')

# Image based subtitle formats: no readable text, so content detection is impossible.
$script:ImageSubtitleExtensions = @('.sup', '.idx', '.sub')

# Subtitle trait flags. Order matters: longest / most specific first.
$script:SubtitleFlagMap = [ordered]@{
    'sdh'    = '(?i)(?:^|[\s._\-\[(])(?:sdh|hearing[\s._-]*impaired|hi)(?:$|[\s._\-\])])'
    'forced' = '(?i)(?:^|[\s._\-\[(])(?:forced|foreign(?:[\s._-]*parts?)?)(?:$|[\s._\-\])])'
    'cc'     = '(?i)(?:^|[\s._\-\[(])(?:cc|closed[\s._-]*caption(?:s|ed)?)(?:$|[\s._\-\])])'
}

# ---------------------------------------------------------------------
# LANGUAGE TABLE
#
# Canonical output is ISO 639-2/B (3 letter) because Plex and Jellyfin
# both parse it unambiguously.
#
# Keys are every token we are willing to accept from a filename. This
# deliberately includes WRONG-but-common tokens: 'cn' is a country code
# for China, not a language, but scene releases use it constantly. Same
# for 'jp' (correct: 'ja'/'jpn'), 'gr' (correct: 'el'/'ell'),
# 'cz' (correct: 'cs'/'ces'), 'dk' (correct: 'da'/'dan'),
# 'se' (correct: 'sv'/'swe'), 'ua' (correct: 'uk'/'ukr').
# ---------------------------------------------------------------------
$script:LanguageMap = @{
    # code            = 3-letter canonical
    'en' = 'eng'; 'eng' = 'eng'; 'english' = 'eng'
    'es' = 'spa'; 'spa' = 'spa'; 'esp' = 'spa'; 'spanish' = 'spa'; 'espanol' = 'spa'; 'castellano' = 'spa'; 'latino' = 'spa'
    'fr' = 'fra'; 'fra' = 'fra'; 'fre' = 'fra'; 'french' = 'fra'; 'francais' = 'fra'
    'de' = 'deu'; 'deu' = 'deu'; 'ger' = 'deu'; 'german' = 'deu'; 'deutsch' = 'deu'
    'it' = 'ita'; 'ita' = 'ita'; 'italian' = 'ita'; 'italiano' = 'ita'
    'pt' = 'por'; 'por' = 'por'; 'portuguese' = 'por'; 'portugues' = 'por'
    'br' = 'por'; 'ptbr' = 'por'; 'pt-br' = 'por'; 'brazilian' = 'por'
    'nl' = 'nld'; 'nld' = 'nld'; 'dut' = 'nld'; 'dutch' = 'nld'; 'nederlands' = 'nld'
    'ru' = 'rus'; 'rus' = 'rus'; 'russian' = 'rus'
    'uk' = 'ukr'; 'ukr' = 'ukr'; 'ua' = 'ukr'; 'ukrainian' = 'ukr'
    'pl' = 'pol'; 'pol' = 'pol'; 'polish' = 'pol'; 'polski' = 'pol'
    'cs' = 'ces'; 'ces' = 'ces'; 'cze' = 'ces'; 'cz' = 'ces'; 'czech' = 'ces'
    'sk' = 'slk'; 'slk' = 'slk'; 'slo' = 'slk'; 'slovak' = 'slk'
    'hu' = 'hun'; 'hun' = 'hun'; 'hungarian' = 'hun'; 'magyar' = 'hun'
    'ro' = 'ron'; 'ron' = 'ron'; 'rum' = 'ron'; 'romanian' = 'ron'
    'bg' = 'bul'; 'bul' = 'bul'; 'bulgarian' = 'bul'
    'el' = 'ell'; 'ell' = 'ell'; 'gre' = 'ell'; 'gr' = 'ell'; 'greek' = 'ell'
    'tr' = 'tur'; 'tur' = 'tur'; 'turkish' = 'tur'; 'turkce' = 'tur'
    'sv' = 'swe'; 'swe' = 'swe'; 'se' = 'swe'; 'swedish' = 'swe'; 'svenska' = 'swe'
    'da' = 'dan'; 'dan' = 'dan'; 'dk' = 'dan'; 'danish' = 'dan'; 'dansk' = 'dan'
    'no' = 'nor'; 'nor' = 'nor'; 'nb' = 'nor'; 'norwegian' = 'nor'; 'norsk' = 'nor'
    'fi' = 'fin'; 'fin' = 'fin'; 'finnish' = 'fin'; 'suomi' = 'fin'
    'is' = 'isl'; 'isl' = 'isl'; 'ice' = 'isl'; 'icelandic' = 'isl'
    'ja' = 'jpn'; 'jpn' = 'jpn'; 'jp' = 'jpn'; 'japanese' = 'jpn'
    'ko' = 'kor'; 'kor' = 'kor'; 'kr' = 'kor'; 'korean' = 'kor'
    'zh' = 'zho'; 'zho' = 'zho'; 'chi' = 'zho'; 'cn' = 'zho'; 'chinese' = 'zho'
    'zh-hans' = 'zho'; 'zh-hant' = 'zho'; 'chs' = 'zho'; 'cht' = 'zho'; 'mandarin' = 'zho'; 'cantonese' = 'zho'
    'th' = 'tha'; 'tha' = 'tha'; 'thai' = 'tha'
    'vi' = 'vie'; 'vie' = 'vie'; 'vn' = 'vie'; 'vietnamese' = 'vie'
    'id' = 'ind'; 'ind' = 'ind'; 'indonesian' = 'ind'; 'bahasa' = 'ind'
    'ms' = 'msa'; 'msa' = 'msa'; 'may' = 'msa'; 'malay' = 'msa'
    'hi' = 'hin'; 'hin' = 'hin'; 'hindi' = 'hin'
    'ta' = 'tam'; 'tam' = 'tam'; 'tamil' = 'tam'
    'te' = 'tel'; 'tel' = 'tel'; 'telugu' = 'tel'
    'bn' = 'ben'; 'ben' = 'ben'; 'bengali' = 'ben'
    'ar' = 'ara'; 'ara' = 'ara'; 'arabic' = 'ara'
    'he' = 'heb'; 'heb' = 'heb'; 'iw' = 'heb'; 'hebrew' = 'heb'
    'fa' = 'fas'; 'fas' = 'fas'; 'per' = 'fas'; 'persian' = 'fas'; 'farsi' = 'fas'
    'hr' = 'hrv'; 'hrv' = 'hrv'; 'croatian' = 'hrv'
    'sr' = 'srp'; 'srp' = 'srp'; 'serbian' = 'srp'
    'sl' = 'slv'; 'slv' = 'slv'; 'slovenian' = 'slv'
    'et' = 'est'; 'est' = 'est'; 'estonian' = 'est'
    'lv' = 'lav'; 'lav' = 'lav'; 'latvian' = 'lav'
    'lt' = 'lit'; 'lit' = 'lit'; 'lithuanian' = 'lit'
    'ca' = 'cat'; 'cat' = 'cat'; 'catalan' = 'cat'
    'eu' = 'eus'; 'eus' = 'eus'; 'baq' = 'eus'; 'basque' = 'eus'
    'gl' = 'glg'; 'glg' = 'glg'; 'galician' = 'glg'
    'hy' = 'hye'; 'hye' = 'hye'; 'armenian' = 'hye'
    'ka' = 'kat'; 'kat' = 'kat'; 'georgian' = 'kat'
    'tl' = 'tgl'; 'tgl' = 'tgl'; 'filipino' = 'tgl'; 'tagalog' = 'tgl'
}

# Human readable names for the canonical codes (used in previews / prompts).
$script:LanguageNames = @{
    'eng' = 'English';    'spa' = 'Spanish';    'fra' = 'French';     'deu' = 'German'
    'ita' = 'Italian';    'por' = 'Portuguese'; 'nld' = 'Dutch';      'rus' = 'Russian'
    'ukr' = 'Ukrainian';  'pol' = 'Polish';     'ces' = 'Czech';      'slk' = 'Slovak'
    'hun' = 'Hungarian';  'ron' = 'Romanian';   'bul' = 'Bulgarian';  'ell' = 'Greek'
    'tur' = 'Turkish';    'swe' = 'Swedish';    'dan' = 'Danish';     'nor' = 'Norwegian'
    'fin' = 'Finnish';    'isl' = 'Icelandic';  'jpn' = 'Japanese';   'kor' = 'Korean'
    'zho' = 'Chinese';    'tha' = 'Thai';       'vie' = 'Vietnamese'; 'ind' = 'Indonesian'
    'msa' = 'Malay';      'hin' = 'Hindi';      'tam' = 'Tamil';      'tel' = 'Telugu'
    'ben' = 'Bengali';    'ara' = 'Arabic';     'heb' = 'Hebrew';     'fas' = 'Persian'
    'hrv' = 'Croatian';   'srp' = 'Serbian';    'slv' = 'Slovenian';  'est' = 'Estonian'
    'lav' = 'Latvian';    'lit' = 'Lithuanian'; 'cat' = 'Catalan';    'eus' = 'Basque'
    'glg' = 'Galician';   'hye' = 'Armenian';   'kat' = 'Georgian';   'tgl' = 'Filipino'
}

# ---------------------------------------------------------------------
# CONTENT BASED LANGUAGE DETECTION
# ---------------------------------------------------------------------

# Unicode script ranges. Script alone identifies the language for most
# non-Latin writing systems; the ambiguous ones are disambiguated below.
$script:ScriptRanges = [ordered]@{
    'Hangul'     = '[\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]'
    'Kana'       = '[\u3040-\u309F\u30A0-\u30FF]'
    'Han'        = '[\u4E00-\u9FFF\u3400-\u4DBF]'
    'Cyrillic'   = '[\u0400-\u04FF]'
    'Arabic'     = '[\u0600-\u06FF\u0750-\u077F]'
    'Hebrew'     = '[\u0590-\u05FF]'
    'Greek'      = '[\u0370-\u03FF\u1F00-\u1FFF]'
    'Thai'       = '[\u0E00-\u0E7F]'
    'Devanagari' = '[\u0900-\u097F]'
    'Tamil'      = '[\u0B80-\u0BFF]'
    'Telugu'     = '[\u0C00-\u0C7F]'
    'Bengali'    = '[\u0980-\u09FF]'
    'Armenian'   = '[\u0530-\u058F]'
    'Georgian'   = '[\u10A0-\u10FF]'
}

# Scripts that map 1:1 onto a language.
$script:ScriptToLanguage = @{
    'Hangul'     = 'kor'
    'Kana'       = 'jpn'
    'Han'        = 'zho'   # only reached when no Kana/Hangul present
    'Hebrew'     = 'heb'
    'Greek'      = 'ell'
    'Thai'       = 'tha'
    'Devanagari' = 'hin'
    'Tamil'      = 'tam'
    'Telugu'     = 'tel'
    'Bengali'    = 'ben'
    'Armenian'   = 'hye'
    'Georgian'   = 'kat'
}

# Cyrillic and Arabic are shared by several languages: distinguish by
# characters unique to each, then fall back to the most common member.
$script:CyrillicHints = [ordered]@{
    'ukr' = '[\u0456\u0457\u0454\u0491]'      # і ї є ґ
    'bul' = '(?:\u044A\u0442|\u0449\u0435\u0442)' # ът, щет
    'srp' = '[\u0452\u0459\u045A\u045B\u045F]'  # ђ љ њ ћ џ
    'rus' = '[\u044B\u044D\u0451\u044A]'        # ы э ё ъ
}
$script:ArabicHints = [ordered]@{
    'fas' = '[\u067E\u0686\u0698\u06AF\u06CC]'  # پ چ ژ گ ی
    'ara' = '[\u0629\u0649\u064A]'              # ة ى ي
}

# Latin-script stop words. Scored by weighted frequency; tokens that are
# highly distinctive get a higher weight than shared ones.
$script:StopWords = @{
    'eng' = @{ 'the'=3; 'and'=2; 'you'=3; 'that'=2; 'this'=2; 'have'=2; 'what'=2; 'with'=2; 'not'=1; 'for'=1; 'are'=1; 'was'=2; 'don''t'=3; 'i''m'=3; 'it''s'=3; 'know'=2; 'here'=1; 'just'=2 }
    'spa' = @{ 'que'=3; 'los'=2; 'las'=2; 'una'=2; 'para'=2; 'esta'=2; 'como'=2; 'pero'=3; 'porque'=3; 'estoy'=3; 'aqui'=2; 'muy'=2; 'todo'=2; 'nada'=2; 'bien'=1; 'senor'=2 }
    'fra' = @{ 'que'=1; 'les'=2; 'des'=2; 'est'=2; 'pas'=3; 'vous'=3; 'pour'=2; 'dans'=2; 'une'=1; 'avec'=2; 'mais'=2; 'c''est'=3; 'je'=2; 'tout'=1; 'plus'=1; 'moi'=2 }
    'deu' = @{ 'der'=3; 'die'=3; 'das'=3; 'und'=2; 'ist'=2; 'nicht'=3; 'sie'=2; 'ich'=3; 'ein'=2; 'mit'=2; 'auf'=2; 'wir'=2; 'was'=1; 'aber'=2; 'noch'=2; 'wie'=1 }
    'ita' = @{ 'che'=3; 'non'=3; 'per'=2; 'una'=1; 'con'=2; 'sono'=2; 'questo'=2; 'come'=1; 'della'=2; 'gli'=2; 'più'=2; 'cosa'=2; 'bene'=1; 'anche'=2 }
    'por' = @{ 'que'=1; 'nao'=3; 'não'=3; 'uma'=2; 'para'=1; 'com'=1; 'voce'=3; 'você'=3; 'isso'=3; 'esta'=1; 'mais'=1; 'como'=1; 'bem'=1; 'muito'=2 }
    'nld' = @{ 'het'=3; 'een'=3; 'niet'=3; 'dat'=2; 'ik'=3; 'je'=2; 'van'=2; 'zijn'=2; 'maar'=2; 'wat'=1; 'heb'=2; 'voor'=2; 'met'=1; 'goed'=1 }
    'pol' = @{ 'nie'=3; 'jest'=3; 'sie'=2; 'się'=3; 'jak'=2; 'tak'=2; 'ale'=2; 'ktore'=2; 'tego'=2; 'czy'=3; 'moze'=2; 'wszystko'=2 }
    'tur' = @{ 'bir'=3; 'bu'=2; 've'=2; 'ne'=1; 'icin'=2; 'için'=3; 'ama'=2; 'daha'=2; 'gibi'=2; 'var'=2; 'yok'=3; 'benim'=2 }
    'swe' = @{ 'att'=3; 'och'=2; 'jag'=3; 'det'=2; 'som'=2; 'inte'=3; 'har'=1; 'med'=1; 'för'=2; 'vad'=1; 'här'=2; 'men'=1 }
    'dan' = @{ 'jeg'=3; 'det'=2; 'ikke'=3; 'og'=2; 'til'=2; 'har'=1; 'med'=1; 'hvad'=2; 'men'=1; 'kan'=1; 'sa'=1; 'nar'=2 }
    'nor' = @{ 'jeg'=3; 'ikke'=3; 'det'=2; 'og'=2; 'til'=2; 'har'=1; 'med'=1; 'hva'=2; 'men'=1; 'kan'=1; 'som'=1; 'ikkje'=3 }
    'fin' = @{ 'että'=3; 'on'=1; 'ei'=2; 'se'=1; 'niin'=2; 'mutta'=3; 'kun'=2; 'olen'=3; 'minä'=3; 'sinä'=3; 'tämä'=3 }
    'ind' = @{ 'yang'=3; 'tidak'=3; 'ini'=2; 'itu'=2; 'dan'=1; 'untuk'=2; 'saya'=3; 'kamu'=2; 'aku'=2; 'akan'=2; 'ada'=1 }
    'vie' = @{ 'không'=3; 'của'=3; 'được'=3; 'người'=3; 'những'=3; 'anh'=2; 'tôi'=3; 'này'=2 }
    'ron' = @{ 'este'=2; 'nu'=1; 'sa'=1; 'sunt'=2; 'pentru'=3; 'care'=2; 'dar'=1; 'mai'=1; 'ce'=1; 'și'=3; 'să'=3 }
    'hun' = @{ 'hogy'=3; 'nem'=2; 'egy'=2; 'az'=2; 'is'=1; 'csak'=3; 'meg'=2; 'volt'=2; 'ez'=1; 'mi'=1 }
    'ces' = @{ 'ne'=1; 'je'=1; 'to'=1; 'se'=1; 'na'=1; 'that'=0; 'jsem'=3; 'nen'=2; 'jsou'=2; 'ale'=1; 'jak'=1; 'když'=3; 'které'=3 }
}

# =====================================================================
# JUNK FILES
# =====================================================================

# Files matching these patterns are candidates for removal when
# -RemoveJunkFiles is supplied. Deliberately conservative: matched files
# must ALSO fall under $JunkSizeCeiling and carry a junk extension.
$script:JunkFilePatterns = @(
    '(?i)^rarbg.*'
    '(?i)^yify.*'
    '(?i)^yts.*'
    '(?i)^etrg.*'
    '(?i)^ripsalot.*'
    '(?i)^ahashare.*'
    '(?i)^torrent[\s._-]*downloaded[\s._-]*from.*'
    '(?i)^downloaded[\s._-]*from.*'
    '(?i)^www[\s._-]*\..*'
    '(?i).*\.(?:com|net|org|to|me|se|eu)[\s._-]*(?:\.txt|\.url|\.nfo)?$'
    '(?i)^read[\s._-]*me.*'
    '(?i)^readme.*'
    '(?i)^info(?:rmation)?$'
    '(?i)^sample.*'
    '(?i)^screenshot.*'
    '(?i)^poster[\s._-]*by.*'
    '(?i)^visit[\s._-]*.*'
    '(?i)^support[\s._-]*(?:us|the).*'
    '(?i)^please[\s._-]*(?:seed|rate).*'
    '(?i)^tracked[\s._-]*by.*'
    '(?i)^proof$'
)

# Extensions eligible for junk removal.
# NOTE: .nfo is deliberately EXCLUDED. Jellyfin and Kodi consume .nfo as
# real metadata, so deleting it by default would be destructive.
$script:JunkExtensions = @(
    '.txt', '.url', '.website', '.lnk', '.htm', '.html', '.md5', '.sfv', '.exe'
    # Mangled / neutered image extensions used by some release groups.
    '.jpg_', '.jpeg_', '.png_', '.gif_', '.bmp_', '.tiff_', '.tif_'
    # Real image extensions: scene banners such as WWW.YTS.AG.jpg.
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.tif'
)

# Anything larger than this is assumed to be a real file the user wants.
$script:JunkSizeCeiling = 10KB

# Per-extension overrides for the ceiling above.
#
# A single global ceiling is the wrong shape for images. Text litter
# (RARBG.txt) really is tiny, but scene banner JPEGs routinely run
# 50-300 KB, so a 10 KB ceiling can never catch them.
#
# Raising the image ceiling is safe because the NAME gate does the real
# work: poster/fanart/folder/banner/cover match nothing in
# $script:JunkFilePatterns, so genuine local artwork is never touched.
$script:JunkSizeCeilingByExtension = @{
    '.jpg'  = 500KB
    '.jpeg' = 500KB
    '.png'  = 500KB
    '.gif'  = 500KB
    '.bmp'  = 500KB
    '.tiff' = 500KB
    '.tif'  = 500KB
}
