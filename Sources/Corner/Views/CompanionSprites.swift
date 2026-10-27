// Pixel art for the companions, one palette letter per pixel ("." is see-through). Every
// character shares the bodies and heads; their own hair, colours and kit go on top. Shared letters:
//   K outline   S skin   s skin shadow   W white   E iris   P blush   M mouth
//   H hair   h hair shadow   L hair shine   A top   a top shadow   B legs   b legs shadow
//   C accent (belt, scarf)   F shoes   X/x hat   G gold   T blade   D wood   N lacquer   R red
// scripts/companion-preview.py draws these straight from this file, for working on the art.

enum Sprites {
    // MARK: Heads (16 × 13; the bottom row sits on the body's neck)

    static let head = """
    .....KKKKKK.....
    ...KKSSSSSSKK...
    ..KSSSSSSSSSSK..
    .KSSSSSSSSSSSSK.
    .KSSSSSSSSSSSSK.
    KSSSSSSSSSSSSSSK
    KSSKKKSSSSKKKSSK
    KSSEWESSSSEWESSK
    KSSEEESSSSEEESSK
    KSPSSSSSSSSSSPSK
    .KSSSSSMMSSSSSK.
    ..KKSSSSSSSSKK..
    ....KKKKKKKK....
    """

    /// Rows 6-11 of the head for each expression.
    static let eyesBlink = """
    KSSSSSSSSSSSSSSK
    KSSSSSSSSSSSSSSK
    KSSKKKSSSSKKKSSK
    KSPSSSSSSSSSSPSK
    .KSSSSSMMSSSSSK.
    ..KKSSSSSSSSKK..
    """
    static let eyesHappy = """
    KSSSKSSSSSSKSSSK
    KSSKSKSSSSKSKSSK
    KSSSSSSSSSSSSSSK
    KSPSSSSSSSSSSPSK
    .KSSSSSMMSSSSSK.
    ..KKSSSMMSSSKK..
    """
    static let eyesSurprised = """
    KSSKKKSSSSKKKSSK
    KSSKWKSSSSKWKSSK
    KSSKKKSSSSKKKSSK
    KSPSSSSSSSSSSPSK
    .KSSSSSKKSSSSSK.
    ..KKSSSSSSSSKK..
    """
    static let eyesYawn = """
    KSSSSSSSSSSSSSSK
    KSSSSSSSSSSSSSSK
    KSSKKKSSSSKKKSSK
    KSPSSSSMMSSSSPSK
    .KSSSSSMMSSSSSK.
    ..KKSSSSSSSSKK..
    """
    /// Looking the way it walks (towards the right; mirrored to walk left).
    static let eyesSide = """
    KSSSKKKSSSSKKKSK
    KSSSEWESSSSEWESK
    KSSSEEESSSSEEESK
    KSSPSSSSSSSSSPSK
    .KSSSSSSMMSSSSK.
    ..KKSSSSSSSSKK..
    """

    // MARK: Bodies (16 wide; row 0 is the neck, the last row the soles)

    static let stand = """
    ......KSSK......
    ....KKAAAAKK....
    ...KAAAACAAAK...
    ..KAKAAACAAKAK..
    ..KAKAAACAAKAK..
    ..KAKAAACAAKAK..
    ..KSKCCCCCCKSK..
    ...KKBBBBBBKK...
    ....KBBBBBBK....
    ....KBBKKBBK....
    ....KBBKKBBK....
    ....KbBKKBbK....
    ...KFFFKKFFFK...
    ...KKKKKKKKKK...
    """
    static let walk = """
    ......KSSK......
    ....KKAAAAKK....
    ...KAAAACAAAK...
    ..KAKAAACAAKAK..
    ..KAKAAACAAKAK..
    ..KSKAAACAAKAK..
    ...KKCCCCCCKSK..
    ....KBBBBBBKK...
    ....KBBBBBBK....
    ...KBBKKKBBK....
    ...KBBK.KBBK....
    ..KBBK...KBBK...
    .KFFFK...KFFFK..
    .KKKKK...KKKKK..
    """
    static let sit = """
    ......KSSK......
    ....KKAAAAKK....
    ...KAAAACAAAK...
    ..KAKAAACAAKAK..
    ..KAKAAACAAKAK..
    ..KSKCCCCCCKSK..
    ..KKBBBBBBBBKK..
    .KBBBBBbbBBBBBK.
    KFFFKBBKKBBKFFFK
    KKKKKKKKKKKKKKKK
    """
    /// Standing with the right arm free, for waving and throwing.
    static let standOneArm = """
    ......KSSK......
    ....KKAAAAKK....
    ...KAAAACAAK....
    ..KAKAAACAAK....
    ..KAKAAACAAK....
    ..KAKAAACAAK....
    ..KSKCCCCCCK....
    ...KKBBBBBBK....
    ....KBBBBBBK....
    ....KBBKKBBK....
    ....KBBKKBBK....
    ....KbBKKBbK....
    ...KFFFKKFFFK...
    ...KKKKKKKKKK...
    """
    /// From behind, for climbing.
    static let back = """
    ......KSSK......
    ....KKAAAAKK....
    ...KAAAAAAAAK...
    ..KAKAAAAAAKAK..
    ..KAKAAAAAAKAK..
    ..KAKaaaaaaKAK..
    ..KSKCCCCCCKSK..
    ...KKBBBBBBKK...
    ....KBBBBBBK....
    ....KBBKKBBK....
    ....KBBKKBBK....
    ....KbBKKBbK....
    ...KFFFKKFFFK...
    ...KKKKKKKKKK...
    """
    /// Arms up (hanging, falling, stretching): the body without its arms; `armUp` goes on top.
    static let reach = """
    ......KSSK......
    ....KKAAAAKK....
    ....KAAACAAK....
    ....KAAACAAK....
    ....KAAACAAK....
    ....KAAACAAK....
    ....KCCCCCCK....
    ....KBBBBBBK....
    ....KBBBBBBK....
    ....KBBKKBBK....
    ....KBBKKBBK....
    ....KbBKKBbK....
    ...KFFFKKFFFK...
    ...KKKKKKKKKK...
    """

    // MARK: Arms, drawn over the head

    /// A raised right arm, from the shoulder (bottom-left) to the hand (top).
    static let armUp = """
    ....KK.
    ...KSSK
    ...KSSK
    ...KAAK
    ...KAAK
    ...KAAK
    ...KAAK
    ...KAAK
    ...KAAK
    ...KAAK
    ...KAAK
    ...KAAK
    ..KAAK.
    .KAAK..
    KAAK...
    KAK....
    KK.....
    """
    /// A right arm out to the side, hand up: waving, throwing.
    static let armWave = """
    .....KK.
    ....KSSK
    ....KSSK
    ...KAAK.
    ..KAAK..
    .KAAK...
    KAAK....
    KAK.....
    KK......
    """

    // MARK: Hair and hats (placed over the head)

    static let ninjaHair = """
    ......K.....K.......
    .K...KHK...KHK...K..
    .KHK.KHHK.KHHK..KHK.
    ..KHKHHHHKHHHHKKHK..
    ..KHHHHHHHHHHHHHHK..
    .KHHHHHHHHHHHHHHHHK.
    KHHHHHLLHHHHHHHHHHHK
    KHHHHHHLLHHHHHHHhHHK
    KHHhHHHHHHHHHHHHHHHK
    KHHHHKHHHHHHKHHHHHHK
    KHHHK.KHHK.KHHK.KHHK
    KHK..............KHK
    KHK..............KHK
    .KK..............KK.
    """
    static let swordsmanHair = """
    ...........KK.......
    ..........KHHK......
    .........KHCCHK.....
    ......KKKKHHKKKK....
    ....KKHHHHHHHHHHKK..
    ...KHHHHHHHHHHHHHHK.
    ..KHHHHLLHHHHHHHHHHK
    .KHHHHHHLHHHHHHHHHHK
    .KHHHHHHHHHHHHHHHHHK
    KHHHHHHHHKKHHHHHHHHK
    KHHHHHHHK..KHHHHHHHK
    KHHK............KHHK
    KHHK............KHHK
    .KHK............KHK.
    ..K..............K..
    """
    static let mageHat = """
    ..............KK......
    .............KXK......
    ............KXXK......
    ...........KXXXK......
    ..........KXXXXK......
    .........KXXXXXK......
    ........KXXXXXXXK.....
    .......KXXXXXXXXK.....
    ......KxxxxGxxxxxK....
    ..KKKKXXXXXXXXXXXXKKKK
    .KXXXXXXXXXXXXXXXXXXXK
    ..KKKKKHHHHHHHHKKKKK..
    ...KHHHHHHHHHHHHHHK...
    ..KHHHLHHHHHHHHHHHHK..
    ..KHHHHHHHHHHHHHHHHK..
    ..KHHHHKHHHHHHKHHHHK..
    .KHHHK..........KHHHK.
    .KHHK............KHHK.
    .KHHK............KHHK.
    .KHHK............KHHK.
    .KHHK............KHHK.
    ..KHK............KHK..
    ...K..............K...
    """

    // MARK: Cat (its own shapes; letters O fur, o stripes, Y cream, P pink, E eyes)

    static let catSit = """
    .K............K.
    .KK..........KK.
    .KOK........KOK.
    .KPOKKKKKKKKOPK.
    KOOOOOOooOOOOOOK
    KOOOOOOooOOOOOOK
    KOOKEOOOOOOKEOOK
    KOOEWOOOOOOEWOOK
    KOOOOOOPPOOOOOOK
    .KOOOOKMMKOOOOK.
    ..KKKOOOOOOKKK..
    ...KOYYYYYYOK...
    ..KOOYYYYYYOOKKK
    ..KOOYYYYYYOOKOK
    ..KOYYKOOKYYOKOK
    ..KKKKKKKKKKKKK.
    """
    /// Rows 6-9 of the cat's face for each expression.
    static let catBlink = """
    KOOOOOOOOOOOOOOK
    KOOKKOOOOOOKKOOK
    KOOOOOOPPOOOOOOK
    .KOOOOKMMKOOOOK.
    """
    static let catHappy = """
    KOOOKOOOOOOKOOOK
    KOOKOKOOOOKOKOOK
    KOOOOOOPPOOOOOOK
    .KOOOOKMMKOOOOK.
    """
    /// Side on, facing right, two steps.
    static let catWalk1 = """
    ...............K..K.
    ..............KOKKOK
    ..............KOOOOK
    KK...........KOOOOOK
    KOK..........KOOOEOK
    .KOK.........KOOOOPK
    ..KOKKKKKKKKKOOOOOK.
    ...KOOOOOOOOOOOKKK..
    ...KOooOOooOOOOK....
    ...KOOOOOOOOOOOK....
    ...KOYKKKKKKKKYK....
    ..KYK.......KYK.....
    ..KK........KK......
    """
    static let catWalk2 = """
    ...............K..K.
    ..............KOKKOK
    ..............KOOOOK
    .............KOOOOOK
    K............KOOOEOK
    KOK..........KOOOOPK
    .KOKKKKKKKKKKOOOOOK.
    ..KOOOOOOOOOOOOKKK..
    ...KOooOOooOOOOK....
    ...KOOOOOOOOOOOK....
    ...KOYKKKKKKKKYK....
    ....KYK....KYK......
    ....KK.....KK.......
    """
    /// Curled up asleep.
    static let catSleep = """
    ..........K..K....
    .........KOKKOK...
    ...KKKKKKKOOOOOK..
    ..KOOOOOOOOOOOOOK.
    .KOOooOOooOOKKOOOK
    KOOOOOOOOOOOOOPOOK
    KOYOOOOOOOOOOOOOK.
    KOOYYYYYYYYYYYYK..
    .KKKKKKKKKKKKKK...
    """
    static let yarn = """
    .KKK.
    KPRPK
    KRPRK
    KPRPK
    .KKK.
    """

    // MARK: Kit and effects

    static let scarf = """
    ..KKKKKKKK..
    .KCCCCCCCCK.
    ..KKCCCCKK..
    """
    /// Trailing behind the ninja, two frames.
    static let scarfTail1 = """
    ......KK.
    ....KKCCK
    ..KKCCCK.
    .KCCCKK..
    KCCKK....
    KKK......
    """
    static let scarfTail2 = """
    .......KK
    .....KKCK
    ...KKCCK.
    KKKCCKK..
    KCCKK....
    .KK......
    """
    static let sheath = """
    ............KK
    ...........KCK
    ..........KCK.
    .........KGGK.
    ........KNK...
    ......KNNK....
    ....KNNK......
    ..KNNK........
    KNNK..........
    KK............
    """
    static let sword = """
    ..........KK
    .........KTK
    ........KTK.
    .......KTK..
    ......KTK...
    .....KTK....
    ..KGKTK.....
    ..KGGK......
    .KDKGK......
    KDK.........
    KK..........
    """
    static let slash = """
    ......WWWW..
    ....WW....W.
    ...W.......W
    ..W.........
    .W..........
    .W..........
    W...........
    """
    static let staff = """
    .KK.
    KGGK
    KGGK
    .KK.
    .KK.
    .KDK
    .KDK
    .KDK
    .KDK
    .KDK
    .KDK
    .KDK
    .KDK
    .KDK
    .KDK
    .KDK
    .KDK
    .KDK
    .KDK
    ..K.
    """
    static let shuriken1 = """
    ..K..
    .KTK.
    KTKTK
    .KTK.
    ..K..
    """
    static let shuriken2 = """
    K...K
    .KTK.
    .TKT.
    .KTK.
    K...K
    """
    static let sparkle = """
    ..G..
    ..G..
    GGWGG
    ..G..
    ..G..
    """
    static let sparkleSmall = """
    .G.
    GWG
    .G.
    """
    static let heart = """
    .KK.KK.
    KRRKRRK
    KRRRRRK
    .KRRRK.
    ..KRK..
    ...K...
    """
    static let zee = """
    KKKK
    ..K.
    .K..
    KKKK
    """
    static let smoke = """
    ..WWW....
    .WWWWWWW.
    WWWWWWWWW
    .WWWWWWW.
    ...WWW...
    """
    static let ball = """
    .KKK.
    KRRWK
    KRRRK
    KRRRK
    .KKK.
    """
}

/// Colours, as 0xRRGGBB, by palette letter. Each character's palette goes over `common`.
enum Palettes {
    static let common: [Character: UInt32] = [
        "K": 0x1E1A2E, "S": 0xFFDCC5, "s": 0xF0B89E, "W": 0xFFFFFF, "P": 0xFF9FB2, "M": 0xC2475E,
        "R": 0xE5484D, "T": 0xDCE6F2, "G": 0xF2C14E, "D": 0x8A5A3B, "N": 0x2B2233,
    ]
    static let ninja: [Character: UInt32] = [
        "H": 0x2C2F5A, "h": 0x1F2147, "L": 0x4B5394, "E": 0x3B6FD9,
        "A": 0x2F4A5C, "a": 0x233847, "B": 0x2F4A5C, "b": 0x233847, "C": 0xD93A3A, "F": 0x1C1F2B,
    ]
    static let swordsman: [Character: UInt32] = [
        "H": 0x2A1E1C, "h": 0x1A1210, "L": 0x4D3833, "E": 0x6B3E26,
        "A": 0xF4F0E6, "a": 0xD9D1C1, "B": 0x34428A, "b": 0x27326B, "C": 0x7A2E3A, "F": 0x6B4A33,
    ]
    static let mage: [Character: UInt32] = [
        "H": 0xF59BC6, "h": 0xD9739F, "L": 0xFFD1E5, "E": 0x8E5BE8,
        "A": 0x7B63D6, "a": 0x5F49B8, "B": 0x7B63D6, "b": 0x5F49B8, "C": 0xF2C14E, "F": 0x3C2E63,
        "X": 0x5B3FC4, "x": 0x452E9E,
    ]
    static let cat: [Character: UInt32] = [
        "O": 0xF4A259, "o": 0xD9822B, "Y": 0xFFE8CC, "P": 0xF7A1B0, "E": 0x2B2233,
    ]
}
