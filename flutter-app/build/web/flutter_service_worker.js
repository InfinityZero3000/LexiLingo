'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "e579b0030f5c0a9ed50dbaf43d0ba8f9",
"version.json": "d39ce5a4121adaef57244b1ee8726a3d",
"index.html": "2804f72a26ab89abc7420fab04bdb8a1",
"/": "2804f72a26ab89abc7420fab04bdb8a1",
"main.dart.js": "58aa87addb997af7f430c65a1aaa706a",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"favicon.png": "11e64950458714ccf4510df80c0aff14",
"icons/Icon-192.png": "f9dc287a770157d028bac468b1e5e805",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"icons/Icon-512.png": "f9dc287a770157d028bac468b1e5e805",
"manifest.json": "875b0b16a1ea97642ce713cad293aabf",
"assets/animation/SuccessCheck.json": "340c29e5c6c44f58232f8802570550e5",
"assets/animation/Confetti.json": "ff63a9b38d34fece66ab25e011855e49",
"assets/animation/HeartBeat.json": "2a04439302fbcc8c974ed931324c6009",
"assets/animation/Welcome.json": "275fc588255973ac1fc59ff6929c3b96",
"assets/animation/PulseLoader.json": "423fdd5b6552875e456dec1fa90f649c",
"assets/animation/SpinningDots.json": "3a7944a9cd8508d8fe636e58704279d9",
"assets/animation/Sandy%2520Loading.json": "225a297da5abf70e8b332d525bf1609a",
"assets/animation/StarBurst.json": "3b841e1b9aff9a7e57e99fc1cc5ed9f9",
"assets/animation/Live%2520Love%2520Learn.json": "90dfe6b3cf8ae8e5aa6a033812bb6d48",
"assets/NOTICES": "cb48cb6dcd8babd3d40e72058af7a6f4",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/AssetManifest.bin.json": "0eb191f082c94d58f0f1d3a49a2e84ec",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/record_web/assets/js/record.fixwebmduration.js": "1f0108ea80c8951ba702ced40cf8cdce",
"assets/packages/record_web/assets/js/record.worklet.js": "6d247986689d283b7e45ccdf7214c2ff",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/AssetManifest.bin": "1c382dc9ab356e652101408710e89dd9",
"assets/fonts/MaterialIcons-Regular.otf": "2f8f36bbe1b4bd48af86a2c4776adb00",
"assets/assets/i18n/ja.json": "5309d3b284a71ec9550f03ee9be84b7f",
"assets/assets/i18n/en.json": "2955794ccaa111f445580342f40fb77f",
"assets/assets/i18n/ko.json": "c1d3d0a3baa5bf7d4f8e9a7808f6dac4",
"assets/assets/i18n/vi.json": "45909cf1a9fbb1c847121837b7d7f80d",
"assets/assets/badges/speed-demon.png": "47e6daaf9b7a9e24b0380afc7390bb2c",
"assets/assets/badges/lv300.png": "ed295ed7f2462513b98f9d8cf18f2dd6",
"assets/assets/badges/streak7.png": "647b1e523183a513b7199439df3329a6",
"assets/assets/badges/social-butterfly.png": "8106e2d9f62bbc8e079398dd703346e0",
"assets/assets/badges/common-lesson.png": "1099d23a56456536195c385d886e3b02",
"assets/assets/badges/voice-pro.png": "afcea52c088f0dea767b369ab7582bb8",
"assets/assets/badges/legendary-vocabulary.png": "0237456350be4fba1a63ba4e39c60c01",
"assets/assets/badges/BADGE_GENERATION_GUIDE.md": "555099318d3808b98054ad2680663506",
"assets/assets/badges/grammar-guardian.png": "be8cd85a636c5426af2ae1a4a23ff424",
"assets/assets/badges/lv100.png": "d2f6f76b4bf51da1594f35ff86535d8b",
"assets/assets/badges/streak14.png": "397b07591f500fe7722b39a886bcd197",
"assets/assets/badges/lv500.png": "8e9515edf1bb498db1823c1177dbd58c",
"assets/assets/badges/badge-viewer.html": "fd2a85e21847c7c8df8d03efd319f948",
"assets/assets/badges/epic-vocabulary.png": "72fcff5fd03c4ca6a10022ed181be91b",
"assets/assets/badges/conversation-champion.png": "8e2f90fdecbffb37438decb62d741d2b",
"assets/assets/badges/comeback-king.png": "89918791947f339fa3b6a42b96a119b8",
"assets/assets/badges/streak3.png": "009052d18c035c210e3711d9daba223e",
"assets/assets/badges/BADGE_FILES_REQUIRED.md": "8c935534d2471a075056856a06e77b9b",
"assets/assets/badges/voice-starter.png": "c8e8ccf8e67c7613de5fe3e9d66b288a",
"assets/assets/badges/challenge-crusher.png": "26bba5ab2ea9ab2c88adb3bb8e231b0b",
"assets/assets/badges/lv200.png": "2edb089a7ddb82d8287437dcf5097ba5",
"assets/assets/badges/culture-explorer.png": "ed137f35316441300037cf4587189a6e",
"assets/assets/badges/perfect-50.png": "2b7b997a8bea5a7ce9b51593ae2da8f3",
"assets/assets/badges/milestone-maker.png": "df5e826f4afeb89ee3ebb309a3ab1e7e",
"assets/assets/badges/listening-legend.png": "e6368c30b213c9ca4669953f02e30aeb",
"assets/assets/badges/moon.png": "7a1a4ce19284178503c96df72f61ec30",
"assets/assets/badges/streak90.png": "6c3cb680d9bf9ae7348fc35891831f95",
"assets/assets/badges/epic-lesson.png": "42b78b25d46a1a7d10e2a1a2209243ff",
"assets/assets/badges/legendary-lesson.png": "dc09ed7a9fbeda38bc20b47792d7575d",
"assets/assets/badges/early-bird.png": "cb31062151199124514fc56c736afc21",
"assets/assets/badges/first-perfect.png": "818b5260522a391bd33e46a65f5e8eb8",
"assets/assets/badges/quiz-champion.png": "acf21d63839e73934503bc8202d8ca20",
"assets/assets/badges/lv25.png": "ea5c1688609fa17e21fe58f2b06bf0c7",
"assets/assets/badges/rare-lesson.png": "d34ec67a96048f3cee071dba146a0e89",
"assets/assets/badges/pronunciation-pro.png": "54557ad473763de0a85370811292a70d",
"assets/assets/badges/streak365.png": "5c7522107d148e4ab3e7279987806051",
"assets/assets/badges/lv150.png": "be59c4337cdee35a015c1c928135144d",
"assets/assets/badges/course-master.png": "ce6ffac71a8975a1d6a56d4c90790626",
"assets/assets/badges/streak30.png": "5c4e3ff29800f4f6eab0ad9e781205ad",
"assets/assets/badges/writing-wizard.png": "94567c85f81dc8451c608e95eab6788c",
"assets/assets/badges/lv50.png": "3058dbef40d1c2c062fc182ae1af478a",
"assets/assets/badges/common-vocabulary.png": "712d8a118880ae41f60df9aed0ea3b7f",
"assets/assets/badges/perfect-10.png": "c858145845f1ce5f95eab2fdc2817dbe",
"assets/assets/badges/100%2525.png": "2b622ceb924fdbb3cac6ec7e38a6d273",
"assets/assets/badges/course-graduate.png": "bec5f3691778d4a41cf83ed06f359118",
"assets/assets/badges/rare-vocabulary.png": "5806ae045bf9969d1ed39439c915260e",
"assets/assets/badges/feedback-friend.png": "845cc38d3481c1286d5703bf46dc12d0",
"assets/assets/login/background-nostar.png": "f5409172a45e52869abc92d020d7da12",
"assets/assets/login/bottom-island.png": "418ca18253c2dc6fcd300d0d6b2a838e",
"assets/assets/login/big-bottom-land.png": "768b26f4818c517eca69e1a3145ea080",
"assets/assets/login/background1.png": "6db47b70fe245925c48c46d385c5117a",
"assets/assets/login/banner.png": "2934da90f049a64a0ed9ee286aadc8db",
"assets/assets/login/bird.png": "b3574bd008bf97038b1c6366392235fe",
"assets/assets/login/background.png": "30d890580e6fec098b0b89734de0cb47",
"assets/assets/login/login-background.png": "2934da90f049a64a0ed9ee286aadc8db",
"assets/assets/login/right-top-island.png": "a47f068889610c3790089ab1eedb8736",
"assets/assets/login/left-top-island.png": "960d6613ba96c2a6c87caef11797976e",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
