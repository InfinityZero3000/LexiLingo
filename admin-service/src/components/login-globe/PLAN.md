# Admin Login — Dotted Globe Background (BlueOrbit-style)

> **Reference**: BlueOrbit Globe Hero (Rive Community)
> **Brand Colors**: Cam `#FF4D00` + Trắng — hệ thống LexiLingo (`--accent: #ff4d00`)

## Mục tiêu
Thay thế CSS blobs hiện tại (`login-blob-1/2/3`) bằng **quả cầu 3D kiểu dot-sphere**
(giống BlueOrbit) — quả cầu được tạo hoàn toàn từ **hàng ngàn chấm nhỏ** (không phải wireframe),
có **chiếu sáng giả** (bright side / dark side), **connection arcs** bay trên bề mặt,
và **atmospheric glow** cam ấm. Globe đặt ở **center-bottom**, nhô lên ~60% viewport,
login card nổi phía trên.

## Phân tích Reference (BlueOrbit)

### Kỹ thuật gốc (Rive)
- 100% procedural, math-driven, Data Binding
- Quả cầu bằng hàng ngàn dot xếp theo Fibonacci sphere
- Ánh sáng giả: dot sáng ở mặt trước, mờ dần về mặt sau → hiệu ứng 3D
- Viền khí quyển (atmosphere rim) phát sáng ở cạnh
- Particle arcs (đường cong kết nối) chạy giữa 2 điểm trên cầu
- Background cực tối, globe là focal point duy nhất

### Chuyển đổi sang Three.js
| Rive concept | Three.js equivalent |
|-------------|-------------------|
| Procedural dots | `Points` + `BufferGeometry` (Fibonacci distribution) |
| Fake lighting | Custom `ShaderMaterial` — dot alpha/size theo `dot(normal, lightDir)` |
| Atmosphere rim | Backface mesh + `ShaderMaterial` Fresnel glow |
| Connection arcs | `TubeGeometry` dọc `CubicBezierCurve3` + animated dash offset |
| Data Binding reactivity | React state → Three.js uniforms |
| Mouse interaction | Damped rotation + GSAP quickTo |

## Thiết kế chi tiết

### Layout tổng thể
```
┌──────────────────────────────────────────────┐
│           Canvas (100vw × 100vh)             │
│                                              │
│           ┌───────────────┐                  │
│           │  Login Card   │  z-index: 10     │
│           │  (glassmorphic│                  │
│           │   dark card)  │                  │
│           └───────────────┘                  │
│                                              │
│          ╭────────────────╮                  │
│        ╱ · ·  · · · · · ·  ╲ ← bright dots  │
│      ╱ · · · ─────→ · · · · ╲ ← arc         │
│     │ · · · · · GLOBE · · · · │              │
│     │ · · · · · · · · · · · · │ atmosphere   │
│      ╲ · · · · · · · · · · ╱   glow rim     │
│        ╲ · · ·  · · · ·  ╱ ← dim dots       │
│          ╰────────────────╯                  │
│     ▼ globe center offset to y = -40%        │
│                                              │
│  ·  ·    ·      ·   ·  ← ambient particles  │
└──────────────────────────────────────────────┘
```

### Thành phần 3D (5 layers)

#### Layer 1: Dot Sphere (core)
- **Geometry**: 2500-3000 điểm phân bố Fibonacci trên mặt cầu `r = 2.5`
- **Material**: Custom `ShaderMaterial`
  - Vertex: tính `vBrightness = dot(normalize(position), uLightDir)`
  - Fragment: circle SDF, alpha = `vBrightness * opacity`, soft edge
- **Fake lighting**: `uLightDir = vec3(0.6, 0.3, 1.0)` — sáng phía trên-phải-trước
- Dots ở mặt tối: `alpha ~0.03-0.08` (vẫn thấy nhưng rất mờ)
- Dots ở mặt sáng: `alpha ~0.5-1.0`, `size ~3-6px`

#### Layer 2: Atmosphere Rim
- Inner sphere (ranh giới cầu) + Fresnel shader
- Phát sáng cam mờ ở **cạnh** (rim/edge), trong suốt ở mặt
- `Fresnel = pow(1.0 - dot(viewDir, normal), 3.0)`
- Color: `#FF6B2C` (cam ấm) → `transparent`
- Mesh: `SphereGeometry(2.55, 64, 64)` — hơi lớn hơn dot sphere
- `side: THREE.BackSide` — chỉ thấy từ trong ra

#### Layer 3: Connection Arcs (6-10 arcs)
- **Path**: `CubicBezierCurve3` — 2 điểm trên mặt cầu, control point nhô ra ngoài
- **Geometry**: `TubeGeometry(curve, 64, 0.008, 8)`
- **Material**: `ShaderMaterial` với:
  - `uProgress` (0→1): animated dash chạy dọc arc
  - `uColor`: gradient cam → trắng
  - Dash head: sáng (glow), tail: mờ dần
- **Traveling dot**: particle sáng chạy dọc arc (sprite nhỏ)
- Stagger: mỗi arc bắt đầu lệch `delay: i * 2s`, loop `duration: 4s`

#### Layer 4: Ambient Particles
- 60-80 hạt nhỏ bay chậm xung quanh globe (ngoài bán kính cầu)
- `Points` + `ShaderMaterial`
- Drift velocity: `sin(time + offset)` trên x/y/z
- Alpha: `0.1-0.3`, size: `1-2px`
- Tạo depth cues, làm scene sống động

#### Layer 5: Background
- CSS `background: #0A0E1A` (rất tối, hơi xanh navy)
- Subtle radial gradient center: `rgba(255, 77, 0, 0.03)` → transparent
- Tạo vùng ấm nhẹ quanh globe

### Bảng màu (Orange/White theme)

| Element | Color | Hex | Notes |
|---------|-------|-----|-------|
| Background | Gần đen ấm | `#0A0E1A` | Navy cực tối |
| BG center glow | Cam cực mờ | `rgba(255, 77, 0, 0.04)` | Radial, subtle |
| Dot bright | Trắng cam | `#FFF5EB` → `#FF8C42` | Phía sáng |
| Dot dim | Cam tối | `rgba(255, 77, 0, 0.06)` | Phía tối |
| Atmosphere rim | Cam ấm | `#FF6B2C` | Fresnel glow |
| Arc gradient | Cam → Trắng | `#FF4D00` → `#FFFFFF` | Head sáng trắng |
| Arc dash head | Trắng sáng | `#FFFFFF` | Glow point |
| Traveling dot | Trắng phát sáng | `#FFFFFF + bloom` | Sprite |
| Ambient particles | Cam mờ | `rgba(255, 140, 66, 0.2)` | Depth cues |
| Login card BG | Trắng trong | `rgba(255, 255, 255, 0.08)` | Glassmorphic dark |
| Card text | Trắng | `#F1F5F9` | High contrast |
| Card accent | Cam brand | `#FF4D00` | Buttons, links |

### Animations chi tiết

| Animation | Engine | Params | Notes |
|-----------|--------|--------|-------|
| Globe auto-rotate | Three.js RAF | `rotateY(0.0008/frame)` | Ultra slow, majestic |
| Dot breathing | Shader uniform | `uTime → sin(time * 0.5) * 0.1` | Subtle size oscillation |
| Light sweep | Shader uniform | `uLightDir` rotate slowly | Light source orbits |
| Arc dash | Shader uniform | `uProgress += 0.003/frame` | Continuous loop |
| Traveling dot | GSAP motionPath | `duration: 4s, repeat: -1` | Particle on curve |
| Atmosphere pulse | Shader uniform | `uGlow = 0.8 + sin(t) * 0.2` | Breathing glow |
| Mouse parallax | GSAP quickTo | `duration: 0.8, ease: power3` | Damped follow |
| Card entrance | GSAP timeline | `y: 60→0, opacity: 0→1, 1.2s` | After globe renders |
| Card field stagger | GSAP timeline | `stagger: 0.08, y: 20→0` | Sequential reveal |

### Tương tác (Interactive Globe)

#### Mouse Move → Globe Rotation
```
onMouseMove:
  targetRotationX = (mouseY - centerY) / height * 0.3   // max ±0.3 rad
  targetRotationY = (mouseX - centerX) / width * 0.5    // max ±0.5 rad

onAnimateFrame:
  globe.rotation.x += (targetRotationX - globe.rotation.x) * 0.02  // damping
  globe.rotation.y += (targetRotationY - globe.rotation.y) * 0.02
  globe.rotation.y += 0.0008  // base auto-rotate continues
```

#### Mouse Proximity → Dot Highlight
- Raycast từ mouse vào sphere
- Dots gần intersection → tăng brightness/size (radius 0.3)
- Shader uniform `uMouseWorld` cập nhật mỗi frame
- `float dist = distance(position, uMouseWorld); brightness += smoothstep(0.3, 0.0, dist);`

#### Touch (Mobile)
- Single finger drag → rotate globe (same as mouse)
- Giảm sensitivity: `* 0.5`

## Cấu trúc files

```
src/components/login-globe/
├── PLAN.md                    ← (file này)
├── GlobeBackground.tsx        ← React component: mount canvas, useEffect init/cleanup
├── globe-scene.ts             ← Scene, Camera, Renderer, resize, RAF loop
├── globe-dots.ts              ← Fibonacci sphere dots + custom ShaderMaterial
├── globe-atmosphere.ts        ← Fresnel rim glow mesh
├── globe-arcs.ts              ← Connection arcs + traveling dots
├── globe-particles.ts         ← Ambient floating particles
├── globe-interaction.ts       ← Mouse/touch handlers, GSAP parallax, raycasting
└── shaders/
    ├── dot.vert.glsl          ← Dot size + brightness calculation
    ├── dot.frag.glsl          ← Circle SDF + alpha fade
    ├── atmosphere.vert.glsl   ← Pass normal + viewDir
    ├── atmosphere.frag.glsl   ← Fresnel rim glow
    ├── arc.vert.glsl          ← Pass UV along tube
    └── arc.frag.glsl          ← Animated dash + glow head
```

## Nhiệm vụ (Tasks)

### Phase 1: Setup & Dot Sphere
- [ ] **T1.1** Cài đặt: `npm i three gsap` + `npm i -D @types/three`
- [ ] **T1.2** Tạo `GlobeBackground.tsx` — canvas mount, useRef, useEffect cleanup
- [ ] **T1.3** Tạo `globe-scene.ts` — Scene, PerspectiveCamera(45°, z=5), Renderer(alpha:true)
- [ ] **T1.4** Tạo `globe-dots.ts` — Fibonacci sphere 2500 points, ShaderMaterial
- [ ] **T1.5** Viết `dot.vert.glsl` + `dot.frag.glsl` — fake lighting, circle SDF
- [ ] **T1.6** RAF loop — globe auto-rotate, render

### Phase 2: Atmosphere & Arcs
- [ ] **T2.1** Tạo `globe-atmosphere.ts` — BackSide sphere + Fresnel shader
- [ ] **T2.2** Viết `atmosphere.vert/frag.glsl` — rim glow cam
- [ ] **T2.3** Tạo `globe-arcs.ts` — 8 CubicBezierCurve3 + TubeGeometry
- [ ] **T2.4** Viết `arc.vert/frag.glsl` — animated dash, glow head
- [ ] **T2.5** Traveling dot sprites dọc arcs

### Phase 3: Particles & Interaction
- [ ] **T3.1** Tạo `globe-particles.ts` — 60 ambient particles, drift motion
- [ ] **T3.2** Tạo `globe-interaction.ts` — mouse parallax (GSAP quickTo)
- [ ] **T3.3** Mouse proximity highlight (raycaster → shader uniform)
- [ ] **T3.4** Touch support cho mobile

### Phase 4: GSAP Animations & Integration
- [ ] **T4.1** Login card entrance timeline (GSAP)
- [ ] **T4.2** Form fields stagger animation
- [ ] **T4.3** Sửa `LoginPage.tsx` — thay CSS blobs → `<GlobeBackground />`
- [ ] **T4.4** Sửa `styles.css`:
  - `.login-page` background → `#0A0E1A`
  - `.login-card` → glassmorphic dark theme
  - Xóa `.login-blob-*` styles
  - Card text → trắng, accent → cam
- [ ] **T4.5** Login card design: dark glassmorphic (dark bg, blur, orange accent border)

### Phase 5: Polish & Optimization
- [ ] **T5.1** Responsive: mobile giảm dots 2500→800, arcs 8→4, particles 60→20
- [ ] **T5.2** Performance: dispose on unmount, DPR cap, lazy init
- [ ] **T5.3** WebGL fallback (static gradient + CSS particles nếu không hỗ trợ)
- [ ] **T5.4** Light sweep animation (uLightDir xoay chậm)
- [ ] **T5.5** Test Chrome, Safari, Firefox, mobile Safari

## Lưu ý kỹ thuật

### Fibonacci Sphere Distribution
```
// Đều khắp mặt cầu, không bị dồn ở cực
for (let i = 0; i < N; i++) {
  const y = 1 - (i / (N - 1)) * 2         // -1 → 1
  const radius = Math.sqrt(1 - y * y)
  const theta = PHI * i                     // PHI = (1 + √5) / 2 * 2π
  const x = Math.cos(theta) * radius
  const z = Math.sin(theta) * radius
  positions.push(x * R, y * R, z * R)
}
```

### Fake Lighting (Dot Shader)
```glsl
// Vertex
varying float vBrightness;
uniform vec3 uLightDir;

void main() {
  vec3 normal = normalize(position);  // sphere surface normal = position
  vBrightness = dot(normal, normalize(uLightDir));
  vBrightness = clamp(vBrightness, 0.05, 1.0);  // never fully black

  // Size varies with brightness
  gl_PointSize = mix(1.5, 5.0, vBrightness) * uScale;
}

// Fragment
varying float vBrightness;
uniform vec3 uColorBright;  // #FFF5EB
uniform vec3 uColorDim;     // #FF4D00

void main() {
  float dist = length(gl_PointCoord - 0.5) * 2.0;
  if (dist > 1.0) discard;  // circle SDF

  float alpha = smoothstep(1.0, 0.3, dist);  // soft edge
  alpha *= vBrightness;

  vec3 color = mix(uColorDim, uColorBright, vBrightness);
  gl_FragColor = vec4(color, alpha * 0.9);
}
```

### Performance Budget
| Element | Vertices | Draw calls |
|---------|----------|-----------|
| Dot sphere | 2500 | 1 (Points) |
| Atmosphere | ~8000 | 1 (Mesh) |
| 8 Arcs | ~4000 | 8 (Mesh) |
| Ambient particles | 60 | 1 (Points) |
| **Total** | **~14,560** | **11** |

→ Rất nhẹ. Mục tiêu 60fps trên MacBook Air M1.

### Mobile Optimizations
- `matchMedia('(max-width: 768px)')` hoặc `navigator.maxTouchPoints > 0`
- Dots: 2500 → 800
- Arcs: 8 → 4
- Particles: 60 → 20
- DPR cap: `Math.min(devicePixelRatio, 1.5)` (thay vì 2)
- Ẩn mouse proximity highlight
- Globe scale: `r = 2.0` (thay vì 2.5)

### UX Safety
- Canvas: `position: fixed; inset: 0; z-index: 0; pointer-events: none`
- Login card: `position: relative; z-index: 10`
- Canvas KHÔNG chặn click — GSI Google button luôn hoạt động
- Globe init async — card hiện ngay (không chờ WebGL ready)
- GSAP card animation chỉ chạy sau khi card DOM mounted

### Login Card (Dark Glassmorphic)
```css
.login-card {
  background: rgba(10, 14, 26, 0.75);
  backdrop-filter: blur(20px) saturate(1.3);
  border: 1px solid rgba(255, 77, 0, 0.15);
  border-radius: 24px;
  box-shadow:
    0 0 80px rgba(255, 77, 0, 0.08),
    0 24px 48px rgba(0, 0, 0, 0.4),
    inset 0 1px 0 rgba(255, 255, 255, 0.05);
  color: #F1F5F9;
}
```
