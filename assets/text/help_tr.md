# Başlarken

TTS Mod Vault, Tabletop Simulator'ın `Mods` ve `Saves` klasörlerini okur, her modu, kaydı ve kayıtlı nesneyi varlık dosyalarının durumuyla birlikte gösterir ve eksik dosyaları indirmenizi, `.ttsmod` yedekleri oluşturmanızı ve geri yüklemenizi sağlar.

- Klasörleri Ayarlar → Klasörler bölümünden ayarlayın. Yedek klasörü isteğe bağlıdır, ancak yedek durumunun açılışlar arasında hatırlanması için gereklidir.
- Kitaplık başlangıçta dizinlenir; uygulama dışında dosyaları değiştirdikten sonra kenar çubuğundaki Yenile'ye tıklayın. "Vault önbelleğini temizle" tüm JSON dosyalarını yeniden okur.
- Modlar, Kayıtlar, Kayıtlı nesneler ve Yedekler listenin üstündeki sekmelerdir. Kayıtlı nesneler Ayarlar → Özellikler bölümünde açıldığında, Yedekler ise bir yedek klasörü ayarlandığında görünür.

# Kitaplık

- Varlıklarını ve işlemlerini görmek için bir moda sol tıklayın
- Daha fazla işlem için bir moda sağ tıklayın (indir, yedekle, klasörü aç, yeniden adlandır, sil, ...)
- Toplu işlemler için birden çok mod seçmek üzere Ctrl+tıklayın (macOS'te Cmd+tıklayın)
- Yedek tarihini ve varlık sayısını görmek için bir modun yedek simgesinin üzerine gelin
- Kaç mod, kayıt ve kayıtlı nesne olduğunu görmek için tür seçicinin üzerine gelin
- Araç çubuğundan arayın, sıralayın ve filtreleyin; toplu işlemler arama metnini ve filtreleri dikkate alır
- Klavye: Ctrl+F aramaya odaklanır, F5 yeniler, Esc seçimi temizler, Delete seçili modu onaydan sonra siler

# Seçili mod

Sağ panel, seçili modun varlıklarını türe göre gruplandırarak listeler. URL renkleri:

- Kırmızı: varlık dosyası eksik
- Yeşil: varlık dosyası indirildi
- Turuncu: bir URL denetimi URL'yi geçersiz olarak işaretledi
- Vurgulu: en son tıkladığınız URL

İşlemler:

- Seçenekleri görmek için bir URL'ye sol veya sağ tıklayın (aç, kopyala, indir, değiştir, dosyayı sil)
- Dosyayı açmak için bir PDF küçük resmine çift tıklayın
- Tümünü indir: tüm eksik varlık dosyalarını indirir. Sonrasında hâlâ eksik olan dosyalar denetlenir: "İndirme denetimi sonuçları" penceresi ulaşılamayan alan adlarını ve artık çalışmayan URL'leri listeler. Bunu Ayarlar → Ağ → İndirmelerden sonra eksik dosyaları denetle bölümünden kapatabilirsiniz
- Bir kartta "3 eksik, 2 geçersiz": 3 dosya eksik ve bir URL denetimi bunların 2'sinin URL'sinin bozuk olduğunu buldu, bu yüzden bu dosyalar indirilemez
- Yedekle: indirilen varlık dosyalarından bir yedek oluşturur
- Ses varlıkları Ayarlar → Özellikler bölümünden genel olarak hariç tutulabilir ve bu ayar her mod için sağ tık menüsünden değiştirilebilir

# Yedekler

- Yedekler, mod JSON'unu, görselini ve indirilen tüm varlık dosyalarını içeren `.ttsmod` arşivleridir.
- Yedek durumu yedeği modla karşılaştırır: güncel, eski (yedekten sonra JSON değişti) veya varlık sayısı uyuşmuyor.
- Kenar çubuğundaki Yedekleri içe aktar, arşivleri Mods klasörüne geri yükler. JSON içe aktar, bir JSON dosyasından mod ekler.
- Toplu yedeklemeler Atla, Değiştir ve Eskiyse değiştir seçeneklerini sunar ve isterseniz sonrasında modun dosyalarını silebilir.

# URL'leri güncelle

URL'leri güncelle özelliği, URL'lerin başlangıcını, hatta URL'lerin tamamını "Eski önek"ten "Yeni önek"e değiştirir.

Birden çok eski öneki `|` (dikey çizgi) simgesiyle ayırarak girebilirsiniz. Ayarlar → URL güncelleme hazır ayarları bölümünde, daha sonra URL'leri güncelle penceresinde sunulacak hazır ayarlar oluşturabilirsiniz.

Tek bir eski önekle:

- Eski önek: `http://pastebin.com/raw.php?i=`
- Yeni önek: `https://pastebin.com/raw/`

Modunuz `http://pastebin.com/raw.php?i=1234` ve `http://pastebin.com/raw.php?i=example` içeriyorsa, bunlar `https://pastebin.com/raw/1234` ve `https://pastebin.com/raw/example` olur.

Birden çok eski önekle:

- Eski önekler: `http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/`
- Yeni önek: `https://pastebin.com/raw/`

Modunuz `http://pastebin.com/raw.php?i=abcd`, `http://pastebin.com/raw/5678` ve `http://pastebin.com/example2` içeriyorsa, bunlar `https://pastebin.com/raw/abcd`, `https://pastebin.com/raw/5678` ve `https://pastebin.com/raw/example2` olur.

# Atölye

- Kenar çubuğundan Steam Atölyesi kimliği veya URL'siyle Atölye modlarını indirin; birden çok kimlik aynı anda girilebilir.
- Atölye'den güncelle, zaten var olan bir modun JSON'unu yeniden indirir. Zorlama seçeneği daha yeni bir yerel dosyanın da üzerine yazar.

# Sorun giderme

- Listenin altındaki Günlük paneli her işlemi ve hatalarını kaydeder; seviyeye ve kaynağa göre filtrelemek, aramak, girdileri kopyalamak veya temizlemek için genişletin. Bir girdiye tıklayarak modunu seçin.
- `vault.log` günlük dosyası veritabanının yanında bulunur. Günlük panelinin başlığından veya Hakkında sekmesinden açın; hata raporlarına ekleyin.
- Klasör değiştirdikten sonra hiçbir şey görünmüyor mu? Yenile'ye tıklayın. Hâlâ yok mu? Ayarlar → Klasörler bölümündeki klasör yollarını ve hariç tutulan alt klasörleri denetleyin.
- Çok sayıda indirme aynı anda çalışırken çalışan URL'ler başarısız mı oluyor? Ayarlar → Ağ bölümünden eşzamanlı indirme sayısını düşürün.
- URL denetimleri ve indirme sonrası denetim önce her alan adına ulaşılıp ulaşılamadığını sınar. Ulaşılamayan bir alan adındaki (kapalı veya ağınızda engellenmiş) URL'ler geçersiz olarak işaretlenmez ve böyle bir alan adı içeren URL denetimi kaydedilmez. Ayarlar → Ağ → Tüm mod ve kayıt alan adlarını denetle, modlarınızın ve kayıtlarınızın kullandığı her alan adını sınar.
