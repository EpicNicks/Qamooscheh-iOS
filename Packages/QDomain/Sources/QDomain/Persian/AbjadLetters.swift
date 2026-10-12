// Generated from web:src/domain/persian/abjad.ts ABJAD_LETTERS (alphabet order). Data only.

import Foundation

public let abjadLetters: [AbjadLetter] = [
    AbjadLetter(
        letter: "ا",
        sound: .a,
        nameNative: "الف",
        nameRomanized: "alef",
        joinsNext: false,
        example: AbjadExample(word: "اسب", romanization: "asb", meaning: "horse"),
        note: "Starting a word, it carries a short vowel (a, e or o); elsewhere it's a long ā. With a madde on top, آ spells ā at the start of a word, as in آب (āb, water)."
    ),
    AbjadLetter(
        letter: "ب",
        sound: .b,
        nameNative: "بِ",
        nameRomanized: "be",
        joinsNext: true,
        example: AbjadExample(word: "بابا", romanization: "bābā", meaning: "dad"),
        note: nil
    ),
    AbjadLetter(
        letter: "پ",
        sound: .p,
        nameNative: "پِ",
        nameRomanized: "pe",
        joinsNext: true,
        example: AbjadExample(word: "پدر", romanization: "pedar", meaning: "father"),
        note: "One of four letters Persian added to the Arabic script: Arabic has no p, so Persian gave ب two more dots."
    ),
    AbjadLetter(
        letter: "ت",
        sound: .t,
        nameNative: "تِ",
        nameRomanized: "te",
        joinsNext: true,
        example: AbjadExample(word: "توت", romanization: "tut", meaning: "mulberry"),
        note: "The everyday t, used in native Persian words. Its twin ط shows up mostly in Arabic loanwords."
    ),
    AbjadLetter(
        letter: "ث",
        sound: .s,
        nameNative: "ثِ",
        nameRomanized: "se",
        joinsNext: true,
        example: AbjadExample(word: "ثانیه", romanization: "sāniye", meaning: "second (time)"),
        note: "In Arabic this is \"th\" as in think. Persian has no th sound, so it's said as a plain s, and it appears almost only in Arabic loanwords."
    ),
    AbjadLetter(
        letter: "ج",
        sound: .j,
        nameNative: "جیم",
        nameRomanized: "jim",
        joinsNext: true,
        example: AbjadExample(word: "جوجه", romanization: "juje", meaning: "chick"),
        note: nil
    ),
    AbjadLetter(
        letter: "چ",
        sound: .ch,
        nameNative: "چِ",
        nameRomanized: "che",
        joinsNext: true,
        example: AbjadExample(word: "چای", romanization: "chāy", meaning: "tea"),
        note: "A Persian addition to the Arabic script: Arabic has no ch, so Persian gave ج three dots."
    ),
    AbjadLetter(
        letter: "ح",
        sound: .h,
        nameNative: "حِ",
        nameRomanized: "he (jimi)",
        joinsNext: true,
        example: AbjadExample(word: "حال", romanization: "hāl", meaning: "state, mood"),
        note: "Arabic's breathy, throaty h. Persian says it as a plain h, the same as ه. Called \"he-ye jimi\" (the ج-shaped h) to tell the two apart."
    ),
    AbjadLetter(
        letter: "خ",
        sound: .kh,
        nameNative: "خِ",
        nameRomanized: "khe",
        joinsNext: true,
        example: AbjadExample(word: "خانه", romanization: "khāne", meaning: "house"),
        note: nil
    ),
    AbjadLetter(
        letter: "د",
        sound: .d,
        nameNative: "دال",
        nameRomanized: "dāl",
        joinsNext: false,
        example: AbjadExample(word: "در", romanization: "dar", meaning: "door"),
        note: nil
    ),
    AbjadLetter(
        letter: "ذ",
        sound: .z,
        nameNative: "ذال",
        nameRomanized: "zāl",
        joinsNext: false,
        example: AbjadExample(word: "ذرت", romanization: "zorrat", meaning: "corn"),
        note: "In Arabic this is \"th\" as in this. Persian says it as z. Mostly in Arabic loanwords, though a few native words keep it, like گذشتن (gozashtan, to pass)."
    ),
    AbjadLetter(
        letter: "ر",
        sound: .r,
        nameNative: "رِ",
        nameRomanized: "re",
        joinsNext: false,
        example: AbjadExample(word: "روز", romanization: "ruz", meaning: "day"),
        note: nil
    ),
    AbjadLetter(
        letter: "ز",
        sound: .z,
        nameNative: "زِ",
        nameRomanized: "ze",
        joinsNext: false,
        example: AbjadExample(word: "زن", romanization: "zan", meaning: "woman"),
        note: "The everyday z, and by far the most common of the four. When unsure how a native Persian word spells z, it's this one."
    ),
    AbjadLetter(
        letter: "ژ",
        sound: .zh,
        nameNative: "ژِ",
        nameRomanized: "zhe",
        joinsNext: false,
        example: AbjadExample(word: "ژاپن", romanization: "zhāpon", meaning: "Japan"),
        note: "A Persian addition to the Arabic script: Arabic has no zh, so Persian gave ز three dots."
    ),
    AbjadLetter(
        letter: "س",
        sound: .s,
        nameNative: "سین",
        nameRomanized: "sin",
        joinsNext: true,
        example: AbjadExample(word: "سیب", romanization: "sib", meaning: "apple"),
        note: "The everyday s, used in native Persian words. ث and ص make the same sound but come from Arabic."
    ),
    AbjadLetter(
        letter: "ش",
        sound: .sh,
        nameNative: "شین",
        nameRomanized: "shin",
        joinsNext: true,
        example: AbjadExample(word: "شب", romanization: "shab", meaning: "night"),
        note: nil
    ),
    AbjadLetter(
        letter: "ص",
        sound: .s,
        nameNative: "صاد",
        nameRomanized: "sād",
        joinsNext: true,
        example: AbjadExample(word: "صبح", romanization: "sobh", meaning: "morning"),
        note: "Arabic's \"heavy\" s, said with the tongue pulled back. Persian flattens it to a plain s; it appears almost only in Arabic loanwords."
    ),
    AbjadLetter(
        letter: "ض",
        sound: .z,
        nameNative: "ضاد",
        nameRomanized: "zād",
        joinsNext: true,
        example: AbjadExample(word: "ضعیف", romanization: "za'if", meaning: "weak"),
        note: "Arabic's heavy d, a sound so distinctive Arabic is nicknamed \"the language of ḍād\". Persian says it as z, only in Arabic loanwords."
    ),
    AbjadLetter(
        letter: "ط",
        sound: .t,
        nameNative: "طا",
        nameRomanized: "tā",
        joinsNext: true,
        example: AbjadExample(word: "طلا", romanization: "talā", meaning: "gold"),
        note: "Arabic's heavy t. Persian says it the same as ت; it appears mostly in Arabic loanwords."
    ),
    AbjadLetter(
        letter: "ظ",
        sound: .z,
        nameNative: "ظا",
        nameRomanized: "zā",
        joinsNext: true,
        example: AbjadExample(word: "ظهر", romanization: "zohr", meaning: "noon"),
        note: "Arabic's heavy \"th\" as in this. Persian says it as z, only in Arabic loanwords."
    ),
    AbjadLetter(
        letter: "ع",
        sound: .glottal,
        nameNative: "عین",
        nameRomanized: "eyn",
        joinsNext: true,
        example: AbjadExample(word: "عسل", romanization: "asal", meaning: "honey"),
        note: "A deep throat sound in Arabic. In Persian it's a light catch in the voice, or silent with the vowel next to it stretched a little. Romanization marks it with ' or leaves it out."
    ),
    AbjadLetter(
        letter: "غ",
        sound: .gh,
        nameNative: "غین",
        nameRomanized: "gheyn",
        joinsNext: true,
        example: AbjadExample(word: "غذا", romanization: "ghazā", meaning: "food"),
        note: "In Arabic, غ (a gargled g) and ق (a k made deep in the throat) are different sounds. Iranian Persian merged them into one, so the spelling just has to be learned."
    ),
    AbjadLetter(
        letter: "ف",
        sound: .f,
        nameNative: "فِ",
        nameRomanized: "fe",
        joinsNext: true,
        example: AbjadExample(word: "فیل", romanization: "fil", meaning: "elephant"),
        note: nil
    ),
    AbjadLetter(
        letter: "ق",
        sound: .gh,
        nameNative: "قاف",
        nameRomanized: "ghāf",
        joinsNext: true,
        example: AbjadExample(word: "قند", romanization: "ghand", meaning: "sugar cube"),
        note: "Arabic's q, made deep in the throat. Iranian Persian says it the same as غ, though some dialects (like Afghan Dari) still keep them apart."
    ),
    AbjadLetter(
        letter: "ک",
        sound: .k,
        nameNative: "کاف",
        nameRomanized: "kāf",
        joinsNext: true,
        example: AbjadExample(word: "کتاب", romanization: "ketāb", meaning: "book"),
        note: nil
    ),
    AbjadLetter(
        letter: "گ",
        sound: .g,
        nameNative: "گاف",
        nameRomanized: "gāf",
        joinsNext: true,
        example: AbjadExample(word: "گل", romanization: "gol", meaning: "flower"),
        note: "A Persian addition to the Arabic script: Arabic has no g, so Persian gave ک a second stroke."
    ),
    AbjadLetter(
        letter: "ل",
        sound: .l,
        nameNative: "لام",
        nameRomanized: "lām",
        joinsNext: true,
        example: AbjadExample(word: "لب", romanization: "lab", meaning: "lip"),
        note: nil
    ),
    AbjadLetter(
        letter: "م",
        sound: .m,
        nameNative: "میم",
        nameRomanized: "mim",
        joinsNext: true,
        example: AbjadExample(word: "ماه", romanization: "māh", meaning: "moon, month"),
        note: nil
    ),
    AbjadLetter(
        letter: "ن",
        sound: .n,
        nameNative: "نون",
        nameRomanized: "nun",
        joinsNext: true,
        example: AbjadExample(word: "نان", romanization: "nān", meaning: "bread"),
        note: nil
    ),
    AbjadLetter(
        letter: "و",
        sound: .v,
        nameNative: "واو",
        nameRomanized: "vāv",
        joinsNext: false,
        example: AbjadExample(word: "ورزش", romanization: "varzesh", meaning: "sport"),
        note: "Three jobs: the consonant v, the long vowel u (دوست, dust, friend), or o (تو, to, you). After خ it's sometimes silent: خواهر is khāhar (sister)."
    ),
    AbjadLetter(
        letter: "ه",
        sound: .h,
        nameNative: "هِ",
        nameRomanized: "he (do-cheshm)",
        joinsNext: true,
        example: AbjadExample(word: "هفت", romanization: "haft", meaning: "seven"),
        note: "The everyday h. At the end of a word it often isn't an h at all but the vowel e, as in خانه (khāne). Called \"he-ye do-cheshm\" (two-eyed h) for its medial shape ـهـ."
    ),
    AbjadLetter(
        letter: "ی",
        sound: .y,
        nameNative: "یِ",
        nameRomanized: "ye",
        joinsNext: true,
        example: AbjadExample(word: "یک", romanization: "yek", meaning: "one"),
        note: "The consonant y or the long vowel i (سیب, sib). Unlike Arabic's ي, Persian ی drops its two dots when it ends a word."
    ),
]
