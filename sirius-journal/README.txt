TRADE JOURNAL (SIRIUS) — to'liq yo'riqnoma

=== 1) APK (GitHub) ===
1. Zip ichidagi HAMMA narsani GitHub repository ildiziga yuklang (.github, scripts, resources, www,
   sirius.keystore, package.json, capacitor.config.json). Repository PRIVATE bo'lsin.
2. Actions > Build APK (5-8 daqiqa) > Releases > SIRIUS-TR-JOURNAL.apk
3. MUHIM (faqat 1 marta): avval ilovada Sozlamalar > Резервное копирование > "Экспорт JSON" qiling,
   eski ilovani o'chiring, yangisini o'rnating, "Импорт JSON" bilan qaytaring.
   Shundan keyin sirius.keystore bir xil bo'lgani uchun har yangi APK eski ustiga o'rnatiladi.
   sirius.keystore ni o'chirmang va o'zgartirmang!

=== 2) FIREBASE (bepul bulut, 2 ta bot kerak emas) ===
1. console.firebase.google.com > Add project (Analytics shart emas).
2. Build > Realtime Database > Create Database > "Start in locked mode".
3. Rules tabiga shuni qo'ying va Publish bosing:
   {"rules":{"sirius":{"$key":{".read":true,".write":true}}}}
4. Data tabidagi manzilni nusxalang: https://XXXX-default-rtdb.firebaseio.com
5. Ilova > Sozlamalar > Облако Firebase: "Сгенерировать ключ" bosing, "Подключить" (URL ilovaga o'rnatilgan).
6. MT5 robotda: FirebaseURL va SyncKey ga xuddi shu URL va kalitni yozing.
   MT5 > Tools > Options > Expert Advisors > Allow WebRequest ga URL ni qo'shing
   (masalan https://XXXX-default-rtdb.firebaseio.com).
Kalit = parol. Uni hech kimga bermang (kamida 24 belgi).

=== 3) MT5 ROBOT (SiriusSync.mq5) ===
MQL5/Experts ga qo'ying, MetaEditor'da F7. Grafikka tashlang. Har bir hisob terminalida alohida.
Birinchi ishga tushganda butun tarix yuboriladi, keyin har ~20 soniyada holat, yopilganda darhol.
Qayta yuborish: ResendHistory=true.
Telegram (ixtiyoriy): BotToken + NotifyChatID = yopilgan sdelka haqida push.

=== 4) QOIDALAR ===
- 0.5R dan kam foydada yopilgan sdelka avtomatik BU (zarar -0.1R dan yomon bo'lsa SL).
  Sdelkani qo'lda o'zgartirsangiz (TP/SL/BU), qayta avtomatik o'zgarmaydi.
- Hisoblar robotdan avtomatik paydo bo'ladi (MT5 login bo'yicha).

=== 5) YANGILANISH (Telegram orqali, ilova ichida) ===
1. Versiyani oshiring: GitHub'da VERSION faylini o'zgartiring (masalan 1.3) va commit qiling.
2. Actions APK ni yig'adi. Telegram kanalga o'zi yuborish uchun repository Settings > Secrets > Actions ga
   TG_TOKEN (bot tokeni) va TG_CHAT (kanal ID) qo'shing. Shunda APK kanalga avtomatik joylanadi va pin qilinadi.
3. Qo'lda: Releases'dan APK ni yuklab, kanalga yuboring. Izohiga "Trade Journal v1.3" deb yozing va xabarni PIN qiling.
4. Ilova soatiga 1 marta (va Настройки > Обновление orqali) pin qilingan xabarni tekshiradi, yangi versiya bo'lsa
   "Обновить" tugmasi chiqadi. Android "noma'lum manbadan o'rnatish" ruxsatini so'raydi (1 marta).
Kalit (sirius.keystore) o'zgarmagani uchun yangilanish eski ustiga xatosiz o'rnatiladi. APK 20 MB dan kichik bo'lishi kerak.

=== 6) 1.3 YANGILIKLARI ===
- "Синхронизировать сейчас" tugmasi o'chirilgan hisoblarni va butun tarixni bulutdan qayta yuklaydi.
  (Avto-sinxron o'chirilgan hisobni qaytarmaydi.)
- Yangi versiya chiqsa, ilova to'xtaydi va "Обязательное обновление" oynasi chiqadi:
  "Скачать и установить" (ilova ichida yuklab, o'rnatuvchini ochadi) va "Открыть в Telegram".
- Birinchi 1.3 ni qo'lda o'rnating. Keyingi versiyalar (1.4, ...) ilova ichidan o'rnatiladi.
