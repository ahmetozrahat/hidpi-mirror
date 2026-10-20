# HiDPI Mirror

Retina olmayan harici monitörlerde (ör. 2560×1440) macOS'un HiDPI ("Retina") çözünürlüklerini açan küçük bir menü çubuğu uygulaması. BetterDisplay'in HiDPI özelliğinin sade bir karşılığı.

## Nasıl çalışır

1. CoreGraphics'in gizli `CGVirtualDisplay` API'siyle HiDPI açık bir sanal ekran oluşturur (ör. 2560×1440 nokta, 5120×2880 piksel).
2. Fiziksel monitörü bu sanal ekranın aynası yapar. macOS masaüstünü 2× çizer, görüntü monitörün yerel çözünürlüğüne küçültülür ve yazılar keskinleşir.
3. Yapılandırma `.forSession` uygulanır, kalıcı hiçbir şey yazılmaz. Uygulama kapanınca monitör normale döner.

Apple Silicon'da `/Library/Displays/.../Overrides` plist yöntemi 1440p panellerde HiDPI modlarını açmadığı için bu yol kullanılıyor.

## Kurulum

```sh
./build.sh --install   # ~/Applications/HiDPI Mirror.app
open ~/Applications/"HiDPI Mirror.app"
```

## Kullanım

- Menü çubuğundaki ekran simgesi: HiDPI aç/kapat, görünüm boyutu seç, girişte başlat.
- **⌃⌥⌘H** her yerden aç/kapat. Görüntü bozulursa önce bunu dene.
- Ayarlar (açık/kapalı, ekran, boyut) hatırlanır, uykudan uyanınca yeniden uygulanır.

## Parlaklık

Aynalama sırasında macOS ve başka uygulamalar (ör. Vorssaint) fiziksel monitörü göremez, bu yüzden parlaklık bu uygulamada.

- Menüdeki kaydırıcı ve klavyedeki parlaklık tuşları (F1/F2) monitörün kendi parlaklığını DDC/CI ile değiştirir. ⌥⇧ ile çeyrek adım.
- Tuşlar için **Erişilebilirlik** izni gerekir (Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik). İzin imzaya bağlı. `build.sh` uygulamayı Developer ID ile imzaladığı için yeniden derlemede izin kaybolmaz.
- Başka bir uygulama da parlaklık tuşlarını dinliyorsa ondaki ekran/parlaklık kontrolünü kapat, yoksa iki uygulama aynı anda yazar.

## Teşhis

```sh
.build/release/HiDPIMirror --probe
```

Monitöre dokunmadan sanal ekranı oluşturur, modlarını listeler ve kaldırır. macOS güncellemesinden sonra API'nin hâlâ çalıştığını kontrol etmek için kullanılır.

```sh
.build/release/HiDPIMirror --ddc        # parlaklığı DDC ile oku
.build/release/HiDPIMirror --ddc 60     # 60'a ayarla, sonra oku
```

## Bilinen sınırlamalar

- Gizli API kullanıyor: App Store'a çıkamaz, bir macOS güncellemesi bozabilir.
- Ayna modunda adaptive sync (VRR) ve HDR büyük ihtimalle devre dışı kalır.
- Süreç sanal ekran kurulurken aniden ölürse sanal ekran oturum kapanana kadar kalabilir. Uygulama bunu tespit edip menüde uyarı gösterir.
