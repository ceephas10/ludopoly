import React from 'react';
import { Emotion, CharacterType } from '../types';

interface TokenCharacterProps {
  emotion: Emotion; // Controls Animation (Physics)
  characterType?: CharacterType;
  visualEmotion?: Emotion; // Controls Face/Skin. Defaults to emotion if not set.
  isTransitioning?: boolean;
  color?: string; // 'blue' | 'red' | 'green' | 'yellow' | 'orange' | 'purple'
  showBoundingBox?: boolean; // Draw black frame around sprite container
  animationKey?: number; // Unique key to force animation restart
  isLooping?: boolean; // Override animations to iterate infinitely
  idleVariant?: number; // 1..5 — selects which idle animation to play
  joyVariant?: number;  // 1..5 — selects which joy animation to play
  variants?: Record<string, number>;
}

export const TokenCharacter: React.FC<TokenCharacterProps> = ({
  emotion, 
  characterType = 'standard',
  visualEmotion,
  isTransitioning = false,
  color = 'blue',
  showBoundingBox = false,
  animationKey = 0,
  isLooping = false,
  idleVariant = 1,
  joyVariant = 1,
  variants = {},
}) => {
  
  const isSleeper = characterType === 'sleeper';
  const effectiveEmotion = isSleeper ? Emotion.IDLE : emotion;
  const displayEmotion = isSleeper ? Emotion.IDLE : (visualEmotion || emotion);
  const isBatman = characterType === 'batman';
  const isInvincible = characterType === 'invincible';
  const isInjured = characterType === 'injured';

  const getAnimationClass = () => {
    const v = variants[emotion] ?? 1;
    const suffix = v === 1 ? '' : `-${v}`;
    // Special case: IDLE has no body animation for variants 1 & 4
    if (emotion === Emotion.IDLE) {
      if (v === 1 || v === 4) return '';
      return `animate-idle-${v}`;
    }
    const baseMap: Record<string, string> = {
      [Emotion.JOY]: 'animate-joy',
      [Emotion.LAUGH]: 'animate-laugh',
      [Emotion.SADNESS]: 'animate-sadness',
      [Emotion.CRY]: 'animate-cry',
      [Emotion.PAIN]: 'animate-pain',
      [Emotion.TERROR]: 'animate-terror',
      [Emotion.PUZZLED]: 'animate-puzzled',
      [Emotion.IMPATIENT]: 'animate-impatient',
      [Emotion.JUMP_RIGHT]: 'animate-jump-right',
      [Emotion.JUMP_LEFT]: 'animate-jump-left',
      [Emotion.JUMP_UP]: 'animate-jump-up',
      [Emotion.JUMP_DOWN]: 'animate-jump-down',
      [Emotion.SLIDE_RIGHT]: 'animate-slide-right',
      [Emotion.SLIDE_LEFT]: 'animate-slide-left',
      [Emotion.SLIDE_UP]: 'animate-slide-up',
      [Emotion.SLIDE_DOWN]: 'animate-slide-down',
    };
    const base = baseMap[emotion];
    if (!base) return '';
    return `${base}${suffix}`;
  };

  const colorPalettes: Record<string, { light: string, main: string, dark: string }> = {
    blue:   { light: '#60a5fa', main: '#3b82f6', dark: '#1e40af' }, 
    red:    { light: '#f87171', main: '#ef4444', dark: '#b91c1c' }, 
    green:  { light: '#4ade80', main: '#22c55e', dark: '#15803d' }, 
    yellow: { light: '#facc15', main: '#eab308', dark: '#a16207' }, 
    orange: { light: '#fb923c', main: '#f97316', dark: '#c2410c' }, 
    purple: { light: '#c084fc', main: '#a855f7', dark: '#7e22ce' }, 
  };

  const palette = colorPalettes[color] || colorPalettes['blue'];

  const renderBatmanEyes = () => (
    <g id="batman-eyes">
      <path d="M 32 45 L 44 42 L 42 48 Z" fill="white" />
      <path d="M 68 45 L 56 42 L 58 48 Z" fill="white" />
    </g>
  );

  const bodyPath = "M 50 140 Q 15 95 15 50 A 35 35 0 1 1 85 50 Q 85 95 50 140 Z";

  // Sphere parameters for tight fit
  const SPHERE_CX = 50;
  const SPHERE_CY = 75;
  const SPHERE_R = 78;

  const CurvedPlaster = ({ x, y, rot }: { x: number, y: number, rot: number }) => (
    <g transform={`translate(${x} ${y}) rotate(${rot})`}>
      <path d="M -22 -6 C -11 -9, 11 -9, 22 -6 L 22 7 C 11 10, -11 10, -22 7 Z" fill="black" opacity="0.1" transform="translate(1, 1)" />
      <path d="M -22 -6 C -11 -9, 11 -9, 22 -6 L 22 6 C 11 9, -11 9, -22 6 Z" fill="#fef3c7" stroke="#d97706" strokeWidth="0.8" />
      <path d="M -4.8 -22 C -7.2 -11, -7.2 11, -4.8 22 L 4.8 22 C 7.2 11, 7.2 -11, 4.8 -22 Z" fill="#fef3c7" stroke="#d97706" strokeWidth="0.8" />
      <rect x="-4.8" y="-6" width="9.6" height="12" fill="#fde68a" />
      <g fill="#d97706" opacity="0.4">
         <circle cx="-14" cy="0" r="0.8" />
         <circle cx="14" cy="0" r="0.8" />
         <circle cx="0" cy="-14" r="0.8" />
         <circle cx="0" cy="14" r="0.8" />
      </g>
    </g>
  );

  // Helper for rendering surface flares with convex "plaqué" rays
  const RenderSurfaceFlare = ({ x, y, scale = 1, rotation = 0, intensity = 1 }: { x: number, y: number, scale?: number, rotation?: number, intensity?: number }) => {
    // Determine vector from sphere center to flare position
    const dx = x - SPHERE_CX;
    const dy = y - SPHERE_CY;
    const dist = Math.sqrt(dx * dx + dy * dy);
    // Direction outward
    const ox = dist > 0 ? dx / dist : 0;
    const oy = dist > 0 ? dy / dist : 0;

    return (
      <g transform={`translate(${x}, ${y}) rotate(${rotation}) scale(${scale})`}>
         <circle cx="0" cy="0" r="10" fill="white" opacity={0.3 * intensity} filter="blur(3px)" />
         <circle cx="0" cy="0" r="5" fill="white" opacity={0.5 * intensity} filter="blur(1px)" />
         
         {/* Convex rays: Bowing TOWARDS the outward vector relative to the chord */}
         {[0, 45, 90, 135, 180, 225, 270, 315].map((angle) => {
            const rad = angle * Math.PI / 180;
            const length = 22;
            const x2 = length * Math.cos(rad);
            const y2 = length * Math.sin(rad);
            
            // Midpoint
            const mx_chord = x2 / 2;
            const my_chord = y2 / 2;
            
            // To wrap around a convex sphere, the curve should bulge AWAY from the chord.
            // If we are looking at the sphere, a surface line bows away from the sphere center.
            // Control point: push it further out from the center than the line segment.
            const bulge = 6;
            const mx = mx_chord + (ox * bulge);
            const my = my_chord + (oy * bulge);

            return (
              <path 
                key={angle}
                d={`M 0 0 Q ${mx} ${my} ${x2} ${y2}`}
                fill="none"
                stroke="white" 
                strokeWidth="2.2" 
                strokeLinecap="round"
                opacity={0.65 * intensity}
              >
                  <animate attributeName="stroke-width" values="1;3.5;1" dur="2s" repeatCount="indefinite" begin={`${(angle/360) + (x/200)}s`} />
                  <animate attributeName="opacity" values="0.2;0.8;0.2" dur="2s" repeatCount="indefinite" begin={`${(angle/360) + (x/200)}s`} />
              </path>
            );
         })}
         <circle cx="0" cy="0" r="3" fill="white" />
      </g>
    );
  };

  return (
    <div 
      className={`
        relative w-[4.32rem] h-[3.84rem] flex items-center justify-center 
        transition-all duration-300 ease-in-out will-change-transform
        ${isTransitioning ? 'opacity-0 scale-50 blur-sm translate-y-4' : 'opacity-100 scale-100 blur-0 translate-y-0'}
        ${showBoundingBox ? 'border border-black' : ''}
      `}
    >
      <div
        key={`${emotion}-${animationKey}-${isLooping ? 'L' : 'N'}-v${variants[emotion] ?? 1}`}
        id="token-body"
        className={`w-full h-full origin-bottom ${getAnimationClass()}`}
        style={isLooping ? { animationIterationCount: 'infinite', animationFillMode: 'none' } : undefined}
      >
        <svg
          viewBox="-50 -50 200 240"
          className="w-full h-full drop-shadow-sm overflow-visible"
          style={{ transform: 'scaleY(0.85)', transformOrigin: 'bottom' }}
          xmlns="http://www.w3.org/2000/svg"
        >
          <defs>
            <radialGradient id={`sphereGradient-${color}`} cx="30%" cy="30%" r="80%">
              <stop offset="0%" stopColor={palette.light} />
              <stop offset="40%" stopColor={palette.main} />
              <stop offset="100%" stopColor={palette.dark} />
            </radialGradient>
            
            <linearGradient id="silverGradient" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor="#f8fafc" />
              <stop offset="50%" stopColor="#cbd5e1" />
              <stop offset="100%" stopColor="#64748b" />
            </linearGradient>

            <linearGradient id="tearGradient" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" stopColor="#e0f2fe" />
              <stop offset="100%" stopColor="#3b82f6" />
            </linearGradient>

            <radialGradient id="haloCore" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="white" stopOpacity="0.8" />
              <stop offset="30%" stopColor="#fff9e6" stopOpacity="0.4" />
              <stop offset="100%" stopColor="rgba(255, 255, 255, 0)" />
            </radialGradient>

            <radialGradient id="haloRainbow" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="rgba(255,255,255,0)" />
              <stop offset="78%" stopColor="rgba(255,255,255,0)" />
              <stop offset="83%" stopColor="rgba(255, 100, 100, 0.2)" />
              <stop offset="86%" stopColor="rgba(100, 255, 100, 0.2)" />
              <stop offset="90%" stopColor="rgba(100, 100, 255, 0.2)" />
              <stop offset="100%" stopColor="rgba(255,255,255,0)" />
            </radialGradient>

            <radialGradient id="sphereBackWall" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="rgba(0,0,0,0.15)" />
              <stop offset="100%" stopColor="rgba(255,255,255,0.1)" />
            </radialGradient>

            <radialGradient id="sphereFrontShell" cx="30%" cy="30%" r="60%">
               <stop offset="0%" stopColor="rgba(255,255,255,0.2)" />
               <stop offset="70%" stopColor="rgba(255,255,255,0)" />
               <stop offset="95%" stopColor="rgba(255,255,255,0.3)" />
            </radialGradient>

            <radialGradient id="specularGlint" cx="25%" cy="25%" r="20%">
               <stop offset="0%" stopColor="white" stopOpacity="0.85" />
               <stop offset="100%" stopColor="white" stopOpacity="0" />
            </radialGradient>

            <radialGradient id="floorShadow" cx="50%" cy="50%" r="50%">
               <stop offset="0%" stopColor="black" stopOpacity="0.4" />
               <stop offset="100%" stopColor="black" stopOpacity="0" />
            </radialGradient>

            <clipPath id="bodyClip">
               <path d={bodyPath} />
            </clipPath>

            <clipPath id="headClip">
              <circle cx="50" cy="50" r="25" />
            </clipPath>
          </defs>

          {/* --- SPHERE BACK LAYER --- */}
          {isInvincible && (
            <g id="sphere-back-group" className="animate-sphere-pulse">
               <circle cx={SPHERE_CX} cy={SPHERE_CY} r={SPHERE_R} fill="url(#sphereBackWall)" />
               <ellipse cx="50" cy="140" rx="25" ry="8" fill="url(#floorShadow)" />
            </g>
          )}

          {/* --- CHARACTER BODY --- */}
          <g id="main-character-group">
            {isBatman && (
              <path
                d="M 25 50 Q 15 68 15 87 Q 16 103 7 119 Q -1 132 0 145 Q 12.5 140.5 25 145 Q 37.5 149.5 50 145 Q 62.5 140.5 75 145 Q 87.5 149.5 100 145 Q 101 132 93 119 Q 84 103 85 87 Q 85 68 75 50 Z"
                fill={palette.dark}
                className={displayEmotion === Emotion.LAUGH ? "animate-cape-laugh" : ""}
              >
                <animate
                  attributeName="d"
                  dur="1.6s"
                  repeatCount="indefinite"
                  calcMode="spline"
                  keyTimes="0;0.25;0.5;0.75;1"
                  keySplines="0.4 0 0.6 1;0.4 0 0.6 1;0.4 0 0.6 1;0.4 0 0.6 1"
                  values="
                    M 25 50 Q 15 68 15 87 Q 16 103 7 119 Q -1 132 0 145 Q 12.5 140.5 25 145 Q 37.5 149.5 50 145 Q 62.5 140.5 75 145 Q 87.5 149.5 100 145 Q 101 132 93 119 Q 84 103 85 87 Q 85 68 75 50 Z;
                    M 25 50 Q 25 68 15 87 Q 6 103 7 119 Q 8 128 0 137.5 Q 12.5 132 25 136 Q 37.5 140 50 135 Q 62.5 131 75 136 Q 87.5 141 100 137.5 Q 91 128 93 119 Q 94 103 85 87 Q 75 68 75 50 Z;
                    M 25 50 Q 25 68 15 87 Q 6 103 7 119 Q 8 124 0 130 Q 12.5 133 25 127.5 Q 37.5 122 50 125 Q 62.5 131 75 127.5 Q 87.5 124 100 130 Q 91 124 93 119 Q 94 103 85 87 Q 75 68 75 50 Z;
                    M 25 50 Q 15 68 15 87 Q 16 103 7 119 Q -1 128 0 137.5 Q 12.5 141 25 136 Q 37.5 131 50 135 Q 62.5 140 75 136 Q 87.5 132 100 137.5 Q 101 128 93 119 Q 84 103 85 87 Q 85 68 75 50 Z;
                    M 25 50 Q 15 68 15 87 Q 16 103 7 119 Q -1 132 0 145 Q 12.5 140.5 25 145 Q 37.5 149.5 50 145 Q 62.5 140.5 75 145 Q 87.5 149.5 100 145 Q 101 132 93 119 Q 84 103 85 87 Q 85 68 75 50 Z
                  "
                />
              </path>
            )}

            <path 
              d={bodyPath} 
              fill="url(#silverGradient)"
              stroke="#94a3b8"
              strokeWidth="1.5"
            >
              {emotion === Emotion.PAIN && !isInvincible && (
                <animate attributeName="fill" values="url(#silverGradient);#f87171;#ef4444;url(#silverGradient)" dur="0.8s" repeatCount={isLooping ? 'indefinite' : 1} />
              )}
            </path>
            
            <circle cx="50" cy="50" r="28" fill="#0f172a" opacity="0.3" />

            <circle cx="50" cy="50" r="25" fill={`url(#sphereGradient-${color})`}>
                {displayEmotion === Emotion.TERROR && (
                    <animate attributeName="fill-opacity" values="1;0.7;1" dur="0.1s" repeatCount={isLooping ? 'indefinite' : 10} />
                )}
            </circle>

            {displayEmotion === Emotion.IMPATIENT && (
              <g id="impatient-arm">
                {/* Left arm (mirrored), so it does not cover the "moi" bubble on the right */}
                <path
                  d="M 24 78 Q 4 38 5 -2"
                  fill="none"
                  stroke="url(#silverGradient)"
                  strokeWidth="14"
                  strokeLinecap="round"
                />
                <path
                  d="M 22 78 Q 6 40 7 -2"
                  fill="none"
                  stroke="#f8fafc"
                  strokeWidth="4"
                  strokeLinecap="round"
                  opacity="0.45"
                />
                {/* Fist (20% bigger) */}
                <ellipse cx="5" cy="-6" rx="11.4" ry="13.2" fill="url(#silverGradient)" stroke="#94a3b8" strokeWidth="1.5" />
                {/* Folded fingers — 3 knuckles drawn on the outer (left) side of the fist */}
                <g>
                  <ellipse cx="-2.5" cy="-14" rx="3.5" ry="2.5" fill="url(#silverGradient)" stroke="#94a3b8" strokeWidth="0.8" />
                  <ellipse cx="-3.5" cy="-7"  rx="3.8" ry="2.5" fill="url(#silverGradient)" stroke="#94a3b8" strokeWidth="0.8" />
                  <ellipse cx="-3"   cy="0"   rx="3.5" ry="2.5" fill="url(#silverGradient)" stroke="#94a3b8" strokeWidth="0.8" />
                  {/* Subtle crease shadows between knuckles */}
                  <path d="M -6 -11 Q -2 -10.5 2 -11" stroke="#64748b" strokeWidth="0.5" fill="none" opacity="0.5" />
                  <path d="M -7 -3.5 Q -2.5 -3 2 -3.5" stroke="#64748b" strokeWidth="0.5" fill="none" opacity="0.5" />
                </g>
                {/* Thumb wrapping around the front of the fist (toward body) */}
                <ellipse cx="14" cy="-4" rx="4.2" ry="6" fill="url(#silverGradient)" stroke="#94a3b8" strokeWidth="1" />
                <ellipse cx="14" cy="-3" rx="2.2" ry="3" fill="#64748b" opacity="0.2" />
                {/* Index finger pointing up (20% bigger) */}
                <rect x="0.8" y="-32" width="8.4" height="26" rx="3.8" fill="url(#silverGradient)" stroke="#94a3b8" strokeWidth="1.2" />
                {/* Knuckle line between index and fist */}
                <path d="M 0.5 -8 Q 5 -7 9.5 -8" stroke="#64748b" strokeWidth="0.6" fill="none" opacity="0.5" />
                {/* Fingertip highlight */}
                <ellipse cx="5" cy="-32" rx="4.2" ry="2.4" fill="#f8fafc" opacity="0.8" />
              </g>
            )}

            {isInjured && (
              <g id="injured-body-decor" clipPath="url(#bodyClip)">
                 <CurvedPlaster x={44} y={108} rot={-10} />
                 <path d="M 25 105 Q 32 102 38 108 Q 30 115 22 110 Z" fill="#991b1b" opacity="0.8" />
                 <path d="M 52 100 Q 60 95 65 102 Q 55 110 50 105 Z" fill="#991b1b" opacity="0.7" />
                 <circle cx="45" cy="120" r="2" fill="#991b1b" opacity="0.6" />
                 <circle cx="48" cy="116" r="1.5" fill="#991b1b" opacity="0.8" />
              </g>
            )}

            {isInjured && (
              <g id="crutch" transform="translate(85, 90) rotate(8)">
                 <rect x="-1.5" y="1" width="4" height="60" fill="black" opacity="0.1" rx="2" />
                 <rect x="-2" y="0" width="4" height="60" fill="#cbd5e1" stroke="#94a3b8" strokeWidth="0.5" rx="2" />
                 <path d="M -10 -4 Q 0 -10 10 -4" fill="none" stroke="#475569" strokeWidth="5" strokeLinecap="round" />
                 <rect x="-6" y="22" width="12" height="4" fill="#475569" rx="2" />
                 <rect x="-3" y="58" width="6" height="3" fill="#1e293b" rx="1" />
              </g>
            )}

            {isInjured && (
              <g id="head-bandage" clipPath="url(#headClip)">
                 <path d="M 15 25 Q 50 50 85 75 L 95 65 Q 50 40 25 15 Z" fill="#fef3c7" stroke="#d97706" strokeWidth="1" />
                 <path d="M 35 36 L 45 42" stroke="#d97706" strokeWidth="0.5" opacity="0.3" />
                 <path d="M 55 48 L 65 54" stroke="#d97706" strokeWidth="0.5" opacity="0.3" />
                 <path d="M 30 20 Q 40 25 35 35 Q 25 30 25 22 Z" fill="#991b1b" opacity="0.5" />
                 <path d="M 60 55 Q 70 60 65 70 Q 55 65 58 58 Z" fill="#991b1b" opacity="0.4" />
              </g>
            )}

            {!isBatman && (
               <ellipse cx="42" cy="38" rx="8" ry="4" fill="white" opacity="0.5" transform="rotate(-30 42 38)" />
            )}

            {isBatman && (
              <path d="M 25 50 L 25 35 L 30 15 L 40 25 L 60 25 L 70 15 L 75 35 L 75 50 Q 50 65 25 50 Z" fill={palette.dark} />
            )}

            {/* --- FACE --- */}
            <g id="face-layer"> 
              {displayEmotion === Emotion.IDLE && !isSleeper && (
                <g id="face-idle">
                  {isBatman ? renderBatmanEyes() : (
                    <g>
                      <circle cx="38" cy="48" r="3.5" fill="white" className={(variants[Emotion.IDLE] ?? 1) === 4 ? 'animate-idle-4-eye' : 'animate-blink'} />
                      <circle cx="62" cy="48" r="3.5" fill="white" className={(variants[Emotion.IDLE] ?? 1) === 4 ? 'animate-idle-4-eye' : 'animate-blink'} />
                    </g>
                  )}
                  <path d="M 42 62 Q 50 66 58 62" stroke={isInjured ? "black" : "white"} strokeWidth="2.5" strokeLinecap="round" fill="none" opacity={isInjured ? 1 : 0.7}/>
                </g>
              )}

              {isSleeper && (
                <g id="face-sleeper">
                  {/* Closed eyes: gentle downward arcs */}
                  <path d="M 32 48 Q 38 54 44 48" stroke="white" strokeWidth="2.5" strokeLinecap="round" fill="none" />
                  <path d="M 56 48 Q 62 54 68 48" stroke="white" strokeWidth="2.5" strokeLinecap="round" fill="none" />
                  {/* Small relaxed mouth */}
                  <path d="M 44 64 Q 50 67 56 64" stroke="white" strokeWidth="2.2" strokeLinecap="round" fill="none" opacity="0.8" />
                  {/* Zzzz: each letter floats up like a snake, growing toward the viewer */}
                  <g style={{ filter: 'drop-shadow(0 1px 1.5px rgba(0,0,0,0.55))' }}>
                    {[
                      { ch: 'Z', x: 56, delay: '0s',    weight: 700 },
                      { ch: 'z', x: 64, delay: '0.5s',  weight: 700 },
                      { ch: 'z', x: 71, delay: '1s',    weight: 700 },
                      { ch: 'z', x: 77, delay: '1.5s',  weight: 700 },
                    ].map((l, i) => (
                      <text
                        key={i}
                        x={l.x}
                        y={76}
                        fill="white"
                        stroke="rgba(30,58,138,0.35)"
                        strokeWidth="0.4"
                        fontSize="16"
                        fontWeight={l.weight}
                        fontFamily="sans-serif"
                        fontStyle="italic"
                        className="animate-zzz-letter"
                        style={{ animationDelay: l.delay }}
                      >
                        {l.ch}
                      </text>
                    ))}
                  </g>
                </g>
              )}

              {displayEmotion === Emotion.JOY && (
                <g id="face-joy">
                  {isBatman ? renderBatmanEyes() : (
                    <g>
                      <path d="M 30 46 Q 38 35 46 46" stroke="white" strokeWidth="3.5" strokeLinecap="round" fill="none" />
                      <path d="M 54 46 Q 62 35 70 46" stroke="white" strokeWidth="3.5" strokeLinecap="round" fill="none" />
                    </g>
                  )}
                  <path d="M 35 62 Q 50 78 65 62" stroke={isInjured ? "black" : "white"} strokeWidth="4" strokeLinecap="round" fill="none" />
                </g>
              )}

              {displayEmotion === Emotion.LAUGH && (
                <g id="face-laugh">
                  {isBatman ? renderBatmanEyes() : (
                    <g>
                      <path d="M 32 48 L 42 40 L 32 32" stroke="white" strokeWidth="4" strokeLinecap="round" fill="none" />
                      <path d="M 68 48 L 58 40 L 68 32" stroke="white" strokeWidth="4" strokeLinecap="round" fill="none" />
                    </g>
                  )}
                  <path d="M 35 58 Q 50 85 65 58 Z" fill={isBatman ? "#1e1e1e" : "#310b0b"} stroke={isInjured ? "black" : "white"} strokeWidth="2" />
                  <path d="M 42 72 Q 50 78 58 72" stroke="#f43f5e" strokeWidth="3" strokeLinecap="round" fill="none" />
                </g>
              )}

              {displayEmotion === Emotion.SADNESS && (
                <g id="face-sadness">
                  {isBatman ? renderBatmanEyes() : (
                    <g>
                      <path d="M 32 44 Q 38 38 44 44" stroke="white" strokeWidth="2" strokeLinecap="round" fill="none" />
                      <path d="M 56 44 Q 62 38 68 44" stroke="white" strokeWidth="2" strokeLinecap="round" fill="none" />
                      <circle cx="38" cy="52" r="3" fill="white" opacity="0.8" />
                      <circle cx="62" cy="52" r="3" fill="white" opacity="0.8" />
                    </g>
                  )}
                  <path d="M 40 70 Q 50 62 60 70" stroke={isInjured ? "black" : "white"} strokeWidth="3" strokeLinecap="round" fill="none" />
                </g>
              )}

              {displayEmotion === Emotion.CRY && (
                <g id="face-cry">
                  {isBatman ? renderBatmanEyes() : (
                    <g>
                      <path d="M 32 45 Q 38 45 44 45" stroke="white" strokeWidth="3" strokeLinecap="round" />
                      <path d="M 56 45 Q 62 45 68 45" stroke="white" strokeWidth="3" strokeLinecap="round" />
                    </g>
                  )}
                  <g>
                     {[0, 0.5].map((delay, i) => (
                       <React.Fragment key={i}>
                         <circle cx="34" cy="52" r="5" fill="url(#tearGradient)" stroke="#1e3a8a" strokeWidth="1.4">
                           <animate attributeName="cy" from="52" to="128" dur="1s" begin={`${delay}s`} repeatCount={isLooping ? 'indefinite' : 1} fill={isLooping ? 'remove' : 'freeze'} />
                           <animate attributeName="opacity" values="0;1;1;0" dur="1s" begin={`${delay}s`} repeatCount={isLooping ? 'indefinite' : 1} fill={isLooping ? 'remove' : 'freeze'} />
                         </circle>
                         <circle cx="66" cy="52" r="5" fill="url(#tearGradient)" stroke="#1e3a8a" strokeWidth="1.4">
                           <animate attributeName="cy" from="52" to="128" dur="0.9s" begin={`${delay + 0.2}s`} repeatCount={isLooping ? 'indefinite' : 1} fill={isLooping ? 'remove' : 'freeze'} />
                           <animate attributeName="opacity" values="0;1;1;0" dur="0.9s" begin={`${delay + 0.2}s`} repeatCount={isLooping ? 'indefinite' : 1} fill={isLooping ? 'remove' : 'freeze'} />
                         </circle>
                       </React.Fragment>
                     ))}
                  </g>
                  <path d="M 42 68 Q 50 62 58 68" stroke={isInjured ? "black" : "white"} strokeWidth="3.5" strokeLinecap="round" fill="none" />
                </g>
              )}

              {displayEmotion === Emotion.TERROR && (
                <g id="face-terror">
                  {isBatman ? renderBatmanEyes() : (
                    <g>
                      <circle cx="38" cy="48" r="10" fill="white" />
                      <circle cx="62" cy="48" r="10" fill="white" />
                      <circle cx="38" cy="48" r="3" fill="black">
                          <animateTransform attributeName="transform" type="translate" values="-2,-2; 2,2; -2,2; 2,-2; -2,-2" dur="0.08s" repeatCount={isLooping ? 'indefinite' : 12} />
                      </circle>
                      <circle cx="62" cy="48" r="3" fill="black">
                           <animateTransform attributeName="transform" type="translate" values="2,-2; -2,2; 2,2; -2,-2; 2,-2" dur="0.08s" repeatCount={isLooping ? 'indefinite' : 12} />
                      </circle>
                    </g>
                  )}
                  <ellipse cx="50" cy="75" rx="12" ry="14" fill="#111" stroke={isInjured ? "black" : "white"} strokeWidth="2">
                     <animate attributeName="ry" values="12;16;12" dur="0.1s" repeatCount={isLooping ? 'indefinite' : 10} />
                  </ellipse>
                </g>
              )}

              {displayEmotion === Emotion.PUZZLED && (
                <g id="face-puzzled">
                  <text x="50" y="145" fill={isInjured ? "#64748b" : palette.main} fontSize="54" fontWeight="bold" fontFamily="serif" textAnchor="middle" opacity="0.9" pointerEvents="none">
                    ?
                    <animate attributeName="y" values="145;115;115" keyTimes="0;0.5;1" dur="2s" repeatCount="indefinite" />
                    <animate attributeName="opacity" values="0;1;1;0" keyTimes="0;0.2;0.8;1" dur="2s" repeatCount="indefinite" />
                  </text>
                  <path d="M 42 68 Q 50 63 58 68" stroke={isInjured ? "black" : "white"} strokeWidth="2.5" strokeLinecap="round" fill="none" />
                </g>
              )}

              {displayEmotion === Emotion.IMPATIENT && (
                <g id="face-impatient">
                  {isBatman ? renderBatmanEyes() : (
                    <g>
                      {/* Joyful eyes: smiling arcs ^ ^ */}
                      <path d="M 30 50 Q 38 42 46 50" stroke="white" strokeWidth="3" strokeLinecap="round" fill="none" />
                      <path d="M 54 50 Q 62 42 70 50" stroke="white" strokeWidth="3" strokeLinecap="round" fill="none" />
                      {/* Cheeks (subtle blush) */}
                      <circle cx="30" cy="60" r="3" fill={palette.light} opacity="0.7" />
                      <circle cx="70" cy="60" r="3" fill={palette.light} opacity="0.7" />
                    </g>
                  )}
                  {/* Big eager smile */}
                  <path d="M 34 62 Q 50 78 66 62" stroke={isInjured ? "black" : "white"} strokeWidth="3.5" strokeLinecap="round" fill="none" />
                  {/* Tongue / lower lip hint */}
                  <path d="M 42 70 Q 50 75 58 70" stroke={isInjured ? "black" : "white"} strokeWidth="2" strokeLinecap="round" fill="none" opacity="0.7" />
                  <g className="animate-moi-bubble" style={isLooping ? { animationIterationCount: 'infinite', animationFillMode: 'none' } : undefined}>
                    <rect x="42" y="-57" width="112" height="52" rx="26" ry="26" fill="white" stroke="#1f2937" strokeWidth="2.5" />
                    <path d="M 72 -6 L 76 24 L 96 -5 Z" fill="white" stroke="#1f2937" strokeWidth="2.5" strokeLinejoin="round" />
                    <rect x="73" y="-7" width="24" height="3.5" fill="white" />
                    <text x="98" y="-18" fontSize="34" fontWeight="bold" fontFamily="sans-serif" textAnchor="middle" fill="#1f2937">moi !</text>
                  </g>
                </g>
              )}

              {displayEmotion === Emotion.PAIN && (
                <g id="face-pain">
                  {isBatman ? renderBatmanEyes() : (
                    <g>
                      <path d="M 30 40 L 45 55 M 45 40 L 30 55" stroke="white" strokeWidth="5" strokeLinecap="round" />
                      <path d="M 55 40 L 70 55 M 70 40 L 55 55" stroke="white" strokeWidth="5" strokeLinecap="round" />
                    </g>
                  )}
                  <path d="M 35 75 L 40 68 L 45 75 L 50 68 L 55 75 L 60 68 L 65 75" stroke={isInjured ? "black" : "white"} strokeWidth="4" fill="none" strokeLinecap="round" strokeLinejoin="round">
                     <animate attributeName="transform" attributeType="XML" type="translate" values="0,0; 0,2; 0,0" dur="0.1s" repeatCount={isLooping ? 'indefinite' : 8} />
                  </path>
                </g>
              )}
            </g>
          </g>

          {/* --- SPHERE FRONT LAYER --- */}
          {isInvincible && (
            <g id="sphere-front-group" className="animate-sphere-pulse">
              <circle cx={SPHERE_CX} cy={SPHERE_CY} r={SPHERE_R + 10} fill="url(#haloCore)" opacity="0.3" />
              <circle cx={SPHERE_CX} cy={SPHERE_CY} r={SPHERE_R} fill="url(#sphereFrontShell)" />
              <circle cx={SPHERE_CX} cy={SPHERE_CY} r={SPHERE_R - 5} fill="url(#haloRainbow)" opacity="0.7">
                  <animateTransform attributeName="transform" type="rotate" from={`0 ${SPHERE_CX} ${SPHERE_CY}`} to={`360 ${SPHERE_CX} ${SPHERE_CY}`} dur="30s" repeatCount="indefinite" />
              </circle>
              <circle cx={SPHERE_CX - 25} cy={SPHERE_CY - 35} r={40} fill="url(#specularGlint)" opacity="0.7" />

              {/* FLARES WITH CORRECT OUTWARD CURVATURE */}
              <RenderSurfaceFlare x={SPHERE_CX - 55} y={SPHERE_CY - 45} scale={1.1} rotation={-15} intensity={0.9} />
              <RenderSurfaceFlare x={SPHERE_CX + 50} y={SPHERE_CY + 40} scale={1.0} rotation={165} intensity={1} />
              <RenderSurfaceFlare x={SPHERE_CX + 45} y={SPHERE_CY - 50} scale={0.8} rotation={45} intensity={0.7} />
            </g>
          )}
        </svg>
      </div>
    </div>
  );
};