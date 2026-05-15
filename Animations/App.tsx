import React, { useState, useEffect, useRef } from 'react';
import { TokenCharacter } from './components/TokenCharacter';

// Auto-load all 36 dice images (6 values × 6 colors)
const DICE_IMAGES = import.meta.glob('./AnimStock/Dices/PNG/Dice_*.png', { eager: true, query: '?url', import: 'default' }) as Record<string, string>;

const EMOTION_LABELS: Record<string, string> = {
  IDLE: 'Repos',
  JOY: 'Joie',
  LAUGH: 'Rire',
  SADNESS: 'Tristesse',
  CRY: 'Pleure',
  PAIN: 'Douleur',
  TERROR: 'Terreur',
  PUZZLED: 'Perplexe',
  IMPATIENT: 'Moi !',
  JUMP_UP: 'Saut Haut',
  JUMP_DOWN: 'Saut Bas',
  JUMP_LEFT: 'Saut Gauche',
  JUMP_RIGHT: 'Saut Droite',
  SLIDE_UP: 'Glisser Haut',
  SLIDE_DOWN: 'Glisser Bas',
  SLIDE_LEFT: 'Glisser Gauche',
  SLIDE_RIGHT: 'Glisser Droite',
};

// Multi-select as chips (compact, click to toggle)
const MultiSelectChips: React.FC<{
  label: string;
  options: { value: string; label: string }[];
  selected: string[];
  onChange: (next: string[]) => void;
}> = ({ label, options, selected, onChange }) => {
  const toggle = (v: string) => {
    if (selected.includes(v)) onChange(selected.filter(x => x !== v));
    else onChange([...selected, v]);
  };
  const allSelected = selected.length === options.length && options.length > 0;
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center justify-between">
        <span className="text-[10px] uppercase tracking-widest text-slate-400 font-bold ml-1">{label}</span>
        <button
          type="button"
          onClick={() => onChange(allSelected ? [] : options.map(o => o.value))}
          className="text-[9px] text-blue-500 hover:underline cursor-pointer"
        >
          {allSelected ? 'Aucun' : 'Tous'}
        </button>
      </div>
      <div className="flex flex-wrap gap-1">
        {options.map(o => (
          <button
            key={o.value}
            type="button"
            onClick={() => toggle(o.value)}
            className={`text-[11px] font-semibold px-2 py-0.5 rounded transition-colors ${
              selected.includes(o.value)
                ? 'bg-blue-600 text-white'
                : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
            }`}
          >
            {o.label}
          </button>
        ))}
      </div>
    </div>
  );
};

// Small 1..5 variant indicator. The "current" variant is highlighted.
// If onSelect is provided, the badges are clickable.
const VariantBadges: React.FC<{ current: number; onSelect?: (n: number) => void }> = ({ current, onSelect }) => (
  <div className="flex justify-between w-full mt-0.5">
    {[1, 2, 3, 4, 5].map(n => (
      <span
        key={n}
        onClick={onSelect ? (e) => { e.stopPropagation(); onSelect(n); } : undefined}
        className={`text-[11px] font-bold rounded px-1.5 leading-tight ${onSelect ? 'cursor-pointer' : ''} ${
          n === current
            ? 'bg-blue-600 text-white'
            : 'bg-slate-200 text-slate-600' + (onSelect ? ' hover:bg-slate-300' : '')
        }`}
      >
        {n}
      </span>
    ))}
  </div>
);

// Selector overlays (active token indicator)
const SELECTOR_GIFS = import.meta.glob('./AnimStock/Selectors/GIF/Selector_*.gif', { eager: true, query: '?url', import: 'default' }) as Record<string, string>;
type SelectorKind = 'none' | 'halo' | 'spotlight' | 'chevron';
const SELECTOR_SRC: Record<Exclude<SelectorKind, 'none'>, string> = {
  halo:      SELECTOR_GIFS['./AnimStock/Selectors/GIF/Selector_A_Halo.gif'],
  spotlight: SELECTOR_GIFS['./AnimStock/Selectors/GIF/Selector_B_Spotlight.gif'],
  chevron:   SELECTOR_GIFS['./AnimStock/Selectors/GIF/Selector_C_Chevron.gif'],
};
const DICE_COLORS = ['blue', 'red', 'green', 'yellow', 'orange', 'purple', 'white'] as const;
type DiceColor = typeof DICE_COLORS[number];
type DiceValue = 1 | 2 | 3 | 4 | 5 | 6;
const getDiceSrc = (value: DiceValue, color: DiceColor): string => {
  const path = `./AnimStock/Dices/PNG/Dice_${value}_${color}.png`;
  return DICE_IMAGES[path];
};
import { Emotion, CharacterType } from './types';
import tokenNomenclatureUrl from '../Documentation/Token_Nomenclature.png?url';
import { 
  Activity, MapPin, Smile, Frown, Zap, AlertTriangle, PlayCircle, 
  Loader2, Camera, X, Save, Check, RotateCcw, Download, Video, 
  Palette, Share2, Film, ArrowRight, ArrowLeft, ArrowUp, 
  ArrowDown, Meh, HelpCircle, User, Image as ImageIcon, MoveHorizontal, Sparkles, Dices
} from 'lucide-react';

declare const GIF: any;

const BG_MAP: Record<string, string> = {
  'green': 'bg-[#00b140]',
  'blue': 'bg-[#0047bb]',
  'white': 'bg-white',
  'black': 'bg-black'
};

const MAIN_BG_OPTIONS: Record<string, string> = {
  'transparent': 'bg-transparent border-none shadow-none',
  'blanc': 'bg-white',
  'noir': 'bg-black',
  'vert': 'bg-[#0d5233]'
};

const BG_REVERSE_MAP: Record<string, string> = Object.entries(BG_MAP).reduce((acc, [key, value]) => {
  acc[value] = key;
  return acc;
}, {} as Record<string, string>);

export default function App() {
  const [currentEmotion, setCurrentEmotion] = useState<Emotion>(Emotion.IDLE);
  const [lastStaticEmotion, setLastStaticEmotion] = useState<Emotion>(Emotion.IDLE);
  const [characterType, setCharacterType] = useState<CharacterType>('standard');
  const [animationKey, setAnimationKey] = useState<number>(0);
  const [activeTab, setActiveTab] = useState<'tokens' | 'dice'>('tokens');
  // Support preview — approximate how big the asset appears on each target device
  // relative to FHD desktop (the studio's reference, 100%). Values combine screen size
  // and PPI to give a roughly realistic relative size for board-game assets.
  type Support = 'smartphone' | 'foldable' | 'tablet' | 'web';
  const SUPPORT_SCALE: Record<Support, number> = {
    smartphone: 0.45,  // iPhone-class ~6", high-PPI but small physical
    foldable: 0.62,    // unfolded ~7.6"
    tablet: 0.82,      // iPad ~10.9"
    web: 1.0,          // FHD desktop reference
  };
  const SUPPORT_LABEL: Record<Support, string> = {
    smartphone: 'Smartphone',
    foldable: 'Smartphone dépliable',
    tablet: 'Tablette',
    web: 'Web (FHD)',
  };
  const [support, setSupport] = useState<Support>('web');
  const [zoom, setZoom] = useState<number>(1);
  const totalScale = SUPPORT_SCALE[support] * zoom;
  const [isLooping, setIsLooping] = useState<boolean>(false);
  const [selector, setSelector] = useState<SelectorKind>('none');
  // Generic variant map: each emotion (and dice anim) has its own variant 1..5
  const [variants, setVariants] = useState<Record<string, number>>({});
  const variantRefForName = useRef<number>(1);
  const getVariant = (key: string) => variants[key] ?? 1;
  const setVariant = (key: string, n: number) => {
    setVariants(prev => ({ ...prev, [key]: n }));
    setAnimationKey(k => k + 1);
  };
  // Legacy refs (kept for code that hasn't been migrated yet)
  const idleVariant = getVariant('IDLE');
  const joyVariant = getVariant('JOY');
  const setIdleVariant = (n: number) => setVariant('IDLE', n);
  const setJoyVariant = (n: number) => setVariant('JOY', n);
  // Refs that mirror state so closures can read fresh values from inside async loops
  const spriteColorRef = useRef('blue');
  const characterTypeRef = useRef<CharacterType>('standard');
  const currentEmotionRef = useRef<Emotion>(Emotion.IDLE);
  const diceValueRefForName = useRef<DiceValue>(1);
  const diceColorRefForName = useRef<DiceColor>('blue');
  const [armedRec, setArmedRec] = useState<'none' | 'gif' | 'webm'>('none');
  const [currentGenerating, setCurrentGenerating] = useState<string | null>(null);
  const [genFormats, setGenFormats] = useState<string[]>(['gif']);
  const [genEmotions, setGenEmotions] = useState<string[]>([Emotion.IDLE]);
  const [genColors, setGenColors] = useState<string[]>(['blue']);
  const [genMovements, setGenMovements] = useState<string[]>([]);
  const [genVariants, setGenVariants] = useState<string[]>(['1']);
  const [genBusy, setGenBusy] = useState<boolean>(false);
  const [nomZoom, setNomZoom] = useState<boolean>(false);
  const [genProgress, setGenProgress] = useState<{ current: number; total: number } | null>(null);
  const genCancelRef = useRef<boolean>(false);
  const [armedDiceRec, setArmedDiceRec] = useState<'none' | 'gif' | 'webm'>('none');
  const [lastTokenRec, setLastTokenRec] = useState<{ url: string; type: 'gif' | 'webm' } | null>(null);
  const [lastDiceRec, setLastDiceRec] = useState<{ url: string; type: 'gif' | 'webm' } | null>(null);
  const [previewOpen, setPreviewOpen] = useState<null | 'tokens' | 'dice'>(null);
  const [externalPreview, setExternalPreview] = useState<null | { url: string; type: 'png' | 'gif' | 'webm'; name: string }>(null);
  const [filePickerOpen, setFilePickerOpen] = useState<null | 'tokens' | 'dice'>(null);
  const [filePickerFiles, setFilePickerFiles] = useState<{ type: 'png' | 'gif' | 'webm'; name: string; mtime: number }[]>([]);

  const openFilePicker = async (kind: 'tokens' | 'dice', type?: 'png' | 'gif' | 'webm') => {
    try {
      const types: ('png' | 'gif' | 'webm')[] = type ? [type] : ['png', 'gif', 'webm'];
      const results = await Promise.all(types.map(async (t) => {
        const res = await fetch(`/api/list?kind=${kind}&type=${t}`);
        const { files } = await res.json();
        return (files as { name: string; mtime: number }[]).map(f => ({ ...f, type: t }));
      }));
      const all = results.flat().sort((a, b) => b.mtime - a.mtime);
      setFilePickerFiles(all);
      setFilePickerOpen(kind);
    } catch (e) {
      console.error('Failed to list files', e);
    }
  };

  const openExternalFile = (kind: 'tokens' | 'dice', type: 'png' | 'gif' | 'webm', name: string) => {
    const url = `/api/file?kind=${kind}&type=${type}&name=${encodeURIComponent(name)}`;
    setExternalPreview({ url, type, name });
    setFilePickerOpen(null);
  };

  const stashRecording = (kind: 'tokens' | 'dice', type: 'gif' | 'webm', blob: Blob) => {
    const url = URL.createObjectURL(blob);
    if (kind === 'tokens') {
      setLastTokenRec(prev => {
        if (prev?.url) URL.revokeObjectURL(prev.url);
        return { url, type };
      });
    } else {
      setLastDiceRec(prev => {
        if (prev?.url) URL.revokeObjectURL(prev.url);
        return { url, type };
      });
    }
  };
  const [diceState, setDiceState] = useState<'idle' | 'rolling' | 'vibrating'>('idle');
  const [diceRollKey, setDiceRollKey] = useState<number>(0);
  const [diceValue, setDiceValue] = useState<DiceValue>(1);
  const [diceColor, setDiceColor] = useState<DiceColor>('blue');
  const [diceDisplayValue, setDiceDisplayValue] = useState<DiceValue>(1);
  const [isDiceLooping, setIsDiceLooping] = useState<boolean>(false);
  const isDiceLoopingRef = useRef<boolean>(false);
  const [lastDiceAnim, setLastDiceAnim] = useState<'lancer' | 'vibrer'>('lancer');
  const lastDiceAnimRef = useRef<'lancer' | 'vibrer'>('lancer');
  const diceFlipTimerRef = useRef<number | null>(null);
  const diceEndTimerRef = useRef<number | null>(null);
  const diceLoopGapRef = useRef<number | null>(null);
  const diceRollingRef = useRef<boolean>(false);

  const clearDiceTimers = () => {
    if (diceFlipTimerRef.current !== null) {
      window.clearInterval(diceFlipTimerRef.current);
      diceFlipTimerRef.current = null;
    }
    if (diceEndTimerRef.current !== null) {
      window.clearTimeout(diceEndTimerRef.current);
      diceEndTimerRef.current = null;
    }
    if (diceLoopGapRef.current !== null) {
      window.clearTimeout(diceLoopGapRef.current);
      diceLoopGapRef.current = null;
    }
  };

  const toggleDiceLoop = () => {
    const next = !isDiceLooping;
    setIsDiceLooping(next);
    isDiceLoopingRef.current = next;
    if (next) {
      // Start looping the last triggered animation
      if (lastDiceAnimRef.current === 'lancer') {
        if (!diceRollingRef.current) rollDice();
      } else {
        setDiceState('vibrating');
      }
    } else {
      // Stop the currently looped animation immediately
      clearDiceTimers();
      diceRollingRef.current = false;
      setDiceState('idle');
    }
  };

  useEffect(() => {
    return clearDiceTimers;
  }, []);

  const rollDice = () => {
    // Prevent re-entry even if button click slips through during state lag
    if (diceRollingRef.current) return;
    // If armed for recording, kick off the recording first (it will animate the roll on canvas)
    const armed = armedDiceRec;
    if (armed !== 'none') {
      setArmedDiceRec('none');
      if (armed === 'gif') { handleDiceGif(); return; }
      if (armed === 'webm') { handleDiceWebm(); return; }
    }
    setLastDiceAnim('lancer');
    lastDiceAnimRef.current = 'lancer';
    diceRollingRef.current = true;
    clearDiceTimers();
    setDiceState('rolling');
    setDiceRollKey(k => k + 1);
    diceFlipTimerRef.current = window.setInterval(() => {
      setDiceDisplayValue((1 + Math.floor(Math.random() * 6)) as DiceValue);
    }, 60);
    diceEndTimerRef.current = window.setTimeout(() => {
      clearDiceTimers();
      const result = (1 + Math.floor(Math.random() * 6)) as DiceValue;
      setDiceValue(result);
      setDiceDisplayValue(result);
      setDiceState('idle');
      diceRollingRef.current = false;
      if (isDiceLoopingRef.current) {
        // Show the result briefly, then roll again
        diceLoopGapRef.current = window.setTimeout(() => {
          if (isDiceLoopingRef.current) rollDice();
        }, 600);
      }
    }, 500);
  };
  const [isPlayingDemo, setIsPlayingDemo] = useState<boolean>(false);
  const [mainBg, setMainBg] = useState<string>('blanc');
  const [spriteColor, setSpriteColor] = useState<string>('blue');
  const [showSavedToast, setShowSavedToast] = useState<boolean>(false);
  const [showShareToast, setShowShareToast] = useState<boolean>(false);
  const [infoMessage, setInfoMessage] = useState<string | null>(null);
  const infoTimerRef = useRef<number | null>(null);
  const [recordingProgress, setRecordingProgress] = useState<number>(0);
  const [isRecordingGif, setIsRecordingGif] = useState<boolean>(false);
  const [isRecordingMp4, setIsRecordingMp4] = useState<boolean>(false);
  const [isTransitioning, setIsTransitioning] = useState<boolean>(false);

  const isActionEmotion = (e: Emotion) => 
    [Emotion.JUMP_RIGHT, Emotion.JUMP_LEFT, Emotion.JUMP_UP, Emotion.JUMP_DOWN, 
     Emotion.SLIDE_RIGHT, Emotion.SLIDE_LEFT, Emotion.SLIDE_UP, Emotion.SLIDE_DOWN].includes(e);

  useEffect(() => {
    const queryString = window.location.href.split('?')[1];
    if (queryString) {
        const params = new URLSearchParams(queryString);
        const urlEmotion = (params.get('e') || params.get('emotion')) as Emotion | null;
        const urlColor = params.get('c') || params.get('color');
        const urlChar = params.get('char') as CharacterType | null;
        const urlMainBg = params.get('mb') || params.get('mainbg');
        
        let hasUrlParams = false;

        if (urlEmotion && Object.values(Emotion).includes(urlEmotion)) {
            setCurrentEmotion(urlEmotion);
            if (!isActionEmotion(urlEmotion)) setLastStaticEmotion(urlEmotion);
            hasUrlParams = true;
        }
        if (urlColor) {
            setSpriteColor(urlColor);
            hasUrlParams = true;
        }
        if (urlChar && ['standard', 'batman', 'invincible', 'injured', 'sleeper', 'none'].includes(urlChar)) {
            setCharacterType(urlChar);
            hasUrlParams = true;
        }
        if (urlMainBg && MAIN_BG_OPTIONS[urlMainBg]) {
            setMainBg(urlMainBg);
            hasUrlParams = true;
        }
        if (hasUrlParams) return; 
    }

    const savedState = localStorage.getItem('ludopoly_token_save');
    if (savedState) {
      try {
        const parsed = JSON.parse(savedState);
        if (parsed.emotion) {
            setCurrentEmotion(parsed.emotion);
            if (!isActionEmotion(parsed.emotion)) setLastStaticEmotion(parsed.emotion);
        }
        if (parsed.mainBg) setMainBg(parsed.mainBg);
        if (parsed.color) setSpriteColor(parsed.color);
        if (parsed.characterType) setCharacterType(parsed.characterType);
      } catch (e) {
        console.error("Failed to load saved state", e);
      }
    }
  }, []);

  const getFilename = (ext: string, kind: 'tokens' | 'dice' = 'tokens', extras?: string) => {
    const variant = variantRefForName.current || 1;
    if (kind === 'dice') {
      const animSuffix = extras ? `_${extras}` : '';
      return `Dice_${diceValueRefForName.current}_${diceColorRefForName.current}${animSuffix}_#${variant}.${ext}`;
    }
    return `Pawn_${characterTypeRef.current}_${spriteColorRef.current}_${currentEmotionRef.current.toLowerCase()}_#${variant}.${ext}`;
  };

  const showInfo = (msg: string) => {
    setInfoMessage(msg);
    if (infoTimerRef.current) window.clearTimeout(infoTimerRef.current);
    infoTimerRef.current = window.setTimeout(() => setInfoMessage(null), 10000);
  };

  const saveBlob = async (blob: Blob, ext: 'png' | 'gif' | 'webm', kind: 'tokens' | 'dice' = 'tokens', extras?: string) => {
    const filename = getFilename(ext, kind, extras);
    const res = await fetch(`/api/save?ext=${ext}&filename=${encodeURIComponent(filename)}&kind=${kind}`, {
      method: 'POST',
      body: blob,
    });
    if (!res.ok) {
      const err = await res.text();
      console.error('Save failed', err);
      showInfo(`Échec sauvegarde ${ext.toUpperCase()} : ${err}`);
      return;
    }
    const { path } = await res.json();
    console.log('Saved to', path);
    showInfo(`${ext.toUpperCase()} sauvegardé : ${path}`);
  };

  const handleSaveState = () => {
    const state = { emotion: currentEmotion, mainBg, color: spriteColor, characterType };
    localStorage.setItem('ludopoly_token_save', JSON.stringify(state));
    setShowSavedToast(true);
    setTimeout(() => setShowSavedToast(false), 2000);
  };

  const handleShare = () => {
    const currentBaseUrl = window.location.href.split('?')[0];
    const params = new URLSearchParams();
    params.set('e', currentEmotion);
    params.set('c', spriteColor);
    params.set('char', characterType);
    params.set('mb', mainBg);
    const shareUrl = `${currentBaseUrl}?${params.toString()}`;
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(shareUrl).then(() => {
          setShowShareToast(true);
          setTimeout(() => setShowShareToast(false), 2000);
      });
    } else {
        window.prompt("Copy link to clipboard: Ctrl+C, Enter", shareUrl);
    }
  };

  const handleReset = () => {
    localStorage.removeItem('ludopoly_token_save');
    window.location.href = window.location.href.split('?')[0];
  };

  const handleEmotion = (newEmotion: Emotion) => {
    setAnimationKey(prev => prev + 1);
    const armed = armedRec;
    if (armed !== 'none') {
      setArmedRec('none');
    }
    if (currentEmotion !== newEmotion) {
      setIsTransitioning(true);
      setTimeout(() => {
        if (!isActionEmotion(newEmotion)) setLastStaticEmotion(newEmotion);
        setCurrentEmotion(newEmotion);
        setIsTransitioning(false);
      }, 300);
    }
    if (armed === 'gif') {
      // Wait until the new emotion has actually rendered (transition is 300ms)
      setTimeout(() => handleRecordGif(), 350);
    } else if (armed === 'webm') {
      setTimeout(() => handleRecordMp4(), 350);
    }
  };

  const handleCharacterChange = (newType: CharacterType) => {
    setCharacterType(newType);
    if (newType === 'sleeper') {
      setCurrentEmotion(Emotion.IDLE);
      setLastStaticEmotion(Emotion.IDLE);
    }
  };

  const playDemoCancelRef = useRef<boolean>(false);
  const playDemo = async () => {
    if (isPlayingDemo) {
      // Toggle off: cancel the running demo
      playDemoCancelRef.current = true;
      return;
    }
    playDemoCancelRef.current = false;
    setIsPlayingDemo(true);
    const sequence = [
      Emotion.JOY, Emotion.LAUGH, Emotion.SADNESS, Emotion.CRY,
      Emotion.PAIN, Emotion.TERROR, Emotion.PUZZLED, Emotion.IMPATIENT, Emotion.JUMP_UP, Emotion.JUMP_DOWN, Emotion.JUMP_RIGHT, Emotion.JUMP_LEFT,
      Emotion.SLIDE_UP, Emotion.SLIDE_DOWN, Emotion.SLIDE_LEFT, Emotion.SLIDE_RIGHT
    ];
    for (const emotion of sequence) {
      if (playDemoCancelRef.current) break;
      handleEmotion(emotion);
      await new Promise(resolve => setTimeout(resolve, 2500));
    }
    handleEmotion(Emotion.IDLE);
    setIsPlayingDemo(false);
    playDemoCancelRef.current = false;
  };

  /**
   * Promise-based frame drawing.
   * Injects animation-delay into the SVG to force internal animations to the correct time.
   */
  const drawFrame = (ctx: CanvasRenderingContext2D, centerX: number, anchorY: number, scale: number, timeOffset: number, bgColor?: string): Promise<void> => {
    return new Promise((resolve) => {
      const tokenBody = document.getElementById('token-body');
      const svgElement = document.querySelector('#studio-sprite svg');
      if (!tokenBody || !svgElement) { resolve(); return; }

      const transform = window.getComputedStyle(tokenBody).transform;
      let svgData = new XMLSerializer().serializeToString(svgElement);

      const styleTags = document.querySelectorAll('style');
      let stylesString = '';
      styleTags.forEach(s => stylesString += s.textContent);

      svgData = svgData.replace('<svg', '<svg width="100" height="140"');
      const timeCorrectionStyle = `* { animation-delay: -${timeOffset.toFixed(3)}s !important; animation-play-state: paused !important; }`;
      svgData = svgData.replace('>', `><style>${stylesString} ${timeCorrectionStyle}</style>`);

      const img = new Image();
      const svgBlob = new Blob([svgData], { type: 'image/svg+xml;charset=utf-8' });
      const url = URL.createObjectURL(svgBlob);

      img.onload = () => {
        if (bgColor) {
          ctx.fillStyle = bgColor;
          ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);
        } else {
          ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
        }
        ctx.save();
        ctx.translate(centerX, anchorY);
        ctx.scale(scale, scale);

        // Apply container-level physics transform (bounces, jumps)
        if (transform && transform !== 'none') {
          const values = transform.split('(')[1].split(')')[0].split(',').map(parseFloat);
          if (values.length === 6) {
            ctx.transform(values[0], values[1], values[2], values[3], values[4], values[5]);
          }
        }

        ctx.drawImage(img, -50, -140, 100, 140);
        ctx.restore();
        URL.revokeObjectURL(url);
        resolve();
      };
      img.src = url;
    });
  };

  const handleRecordGif = async (): Promise<void> => {
    if (isRecordingGif || isRecordingMp4) return;
    setIsRecordingGif(true);
    setRecordingProgress(0);

    try {
      const workerBlob = await fetch('https://cdnjs.cloudflare.com/ajax/libs/gif.js/0.2.0/gif.worker.js').then(r => r.blob());
      const workerUrl = URL.createObjectURL(workerBlob);
      // Sentinel color (#00ff00) → encoded as transparent in the output GIF.
      // Canvas tightly fitted around the token at 1.5x scale (150×210) plus the maximum
      // vertical animation amplitudes (jump-up -72 CSS × 1.5 = -108, slide-down +64 × 1.5 = +96).
      const TRANSPARENT_KEY = 0x00ff00;
      const W = 200, H = 440;
      const ANCHOR_Y = 340;   // = H - 100, leaves room for slide-down (96) below and jump-up (108) above
      const gif = new GIF({ workers: 4, quality: 10, width: W, height: H, transparent: TRANSPARENT_KEY, workerScript: workerUrl });

      const canvas = document.createElement('canvas');
      canvas.width = W;
      canvas.height = H;
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      if (!ctx) return;

      const totalDuration = 2000;
      const fps = 20;
      const frameInterval = 1000 / fps;
      const framesCount = totalDuration / frameInterval;

      setAnimationKey(prev => prev + 1);

      for (let i = 0; i < framesCount; i++) {
        const currentTimeOffset = (i * frameInterval) / 1000;
        await drawFrame(ctx, W / 2, ANCHOR_Y, 1.5, currentTimeOffset, '#00ff00');
        gif.addFrame(ctx.canvas, { copy: true, delay: frameInterval });
        setRecordingProgress(Math.round(((i + 1) / framesCount) * 100));
        await new Promise(r => setTimeout(r, 5));
      }

      await new Promise<void>((resolve) => {
        gif.on('finished', async (blob: Blob) => {
          stashRecording('tokens', 'gif', blob);
          await saveBlob(blob, 'gif');
          setIsRecordingGif(false);
          setRecordingProgress(0);
          URL.revokeObjectURL(workerUrl);
          resolve();
        });
        gif.render();
      });
    } catch (e) {
      console.error("Recording failed", e);
      setIsRecordingGif(false);
    }
  };

  // Sync refs used by getFilename so async loops always read fresh state
  useEffect(() => { spriteColorRef.current = spriteColor; }, [spriteColor]);
  useEffect(() => { characterTypeRef.current = characterType; }, [characterType]);
  useEffect(() => { currentEmotionRef.current = currentEmotion; }, [currentEmotion]);
  useEffect(() => { diceValueRefForName.current = diceValue; }, [diceValue]);
  useEffect(() => { diceColorRefForName.current = diceColor; }, [diceColor]);
  useEffect(() => { variantRefForName.current = getVariant(currentEmotion); }, [currentEmotion, variants]);

  // Generic batch generator exposed on window for the /api/generate endpoint.
  // Spec example for tokens:
  //   { kind: 'tokens', characters: ['standard'], colors: ['blue','red'],
  //     emotions: ['IDLE'], formats: ['gif'] }
  type GenerateSpec = {
    kind: 'tokens';
    characters: string[];
    colors: string[];
    emotions: string[];           // Emotion enum string keys
    formats: ('gif' | 'webm' | 'png')[];
    variants?: number[];          // 1..5 — defaults to [1] if omitted
  };

  const studioGenerate = async (spec: GenerateSpec) => {
    if (isRecordingGif || isRecordingMp4) return { error: 'Recording already in progress' };
    const saved = { color: spriteColor, character: characterType, emotion: currentEmotion };
    const variantList = (spec.variants && spec.variants.length > 0) ? spec.variants : [1];
    const total = spec.characters.length * spec.colors.length * spec.emotions.length * variantList.length * spec.formats.length;
    let current = 0;
    genCancelRef.current = false;
    setGenProgress({ current: 0, total });
    setActiveTab('tokens');
    let canceled = false;
    if (spec.kind === 'tokens') {
      outer: for (const character of spec.characters) {
        setCharacterType(character as CharacterType);
        for (const color of spec.colors) {
          setSpriteColor(color);
          for (const emotionStr of spec.emotions) {
            const emotion = emotionStr as Emotion;
            setCurrentEmotion(emotion);
            if (!isActionEmotion(emotion)) setLastStaticEmotion(emotion);
            for (const variant of variantList) {
              setVariants(prev => ({ ...prev, [emotion]: variant }));
              await new Promise(r => setTimeout(r, 400));
              for (const format of spec.formats) {
                if (genCancelRef.current) { canceled = true; break outer; }
                const filename = `Pawn_${character}_${color}_${emotion.toLowerCase()}_#${variant}.${format}`;
                current++;
                setGenProgress({ current, total });
                setCurrentGenerating(filename);
                if (format === 'gif')  await handleRecordGif();
                else if (format === 'webm') await handleRecordMp4();
                else if (format === 'png')  await handleDownloadPng();
              }
            }
          }
        }
      }
    }
    setCurrentGenerating(null);
    setGenProgress(null);
    setSpriteColor(saved.color);
    setCharacterType(saved.character);
    setCurrentEmotion(saved.emotion);
    return { ok: true, canceled };
  };

  useEffect(() => {
    (window as any).studioGenerate = studioGenerate;
  });

  const handleRecordMp4 = async (): Promise<void> => {
    if (isRecordingGif || isRecordingMp4) return;
    setIsRecordingMp4(true);
    setRecordingProgress(0);

    const W = 200, H = 440;
    const ANCHOR_Y = 340;
    const canvas = document.createElement('canvas');
    canvas.width = W;
    canvas.height = H;
    canvas.style.position = 'fixed';
    canvas.style.left = '-9999px';
    canvas.style.top = '-9999px';
    canvas.style.opacity = '0';
    document.body.appendChild(canvas);
    const ctx = canvas.getContext('2d');
    if (!ctx) { document.body.removeChild(canvas); return; }

    await drawFrame(ctx, W / 2, ANCHOR_Y, 1.5, 0);

    const stream = canvas.captureStream(30);
    const mimeType = MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
      ? 'video/webm;codecs=vp9'
      : MediaRecorder.isTypeSupported('video/webm;codecs=vp8')
        ? 'video/webm;codecs=vp8'
        : 'video/webm';
    const mediaRecorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond: 4_000_000 });
    const chunks: Blob[] = [];

    let resolveDone: () => void;
    const done = new Promise<void>((r) => { resolveDone = r; });

    mediaRecorder.ondataavailable = (e) => { if (e.data && e.data.size > 0) chunks.push(e.data); };
    mediaRecorder.onstop = async () => {
      const blob = new Blob(chunks, { type: 'video/webm' });
      document.body.removeChild(canvas);
      stashRecording('tokens', 'webm', blob);
      await saveBlob(blob, 'webm');
      setIsRecordingMp4(false);
      setRecordingProgress(0);
      resolveDone();
    };

    mediaRecorder.start(100);
    setAnimationKey(prev => prev + 1);

    const duration = 2000;
    const fps = 30;
    const framesCount = (duration / 1000) * fps;

    for (let i = 0; i < framesCount; i++) {
      const timeOffset = i / fps;
      await drawFrame(ctx, W / 2, ANCHOR_Y, 1.5, timeOffset);
      setRecordingProgress(Math.round(((i + 1) / framesCount) * 100));
      await new Promise(r => setTimeout(r, 1000 / fps));
    }
    await new Promise(r => setTimeout(r, 200));
    mediaRecorder.stop();
    await done;
  };

  const handleDownloadPng = async () => {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 1024;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    await drawFrame(ctx, 512, 900, 6.0, 0);
    const blob: Blob | null = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    if (!blob) return;
    await saveBlob(blob, 'png');
  };

  // === DICE EXPORT ===
  // Keyframes from CSS `dice-roll` animation
  const DICE_KEYFRAMES = [
    { t: 0.00, tx: 0,   ty: 0,   rot: 0,    s: 1.00, b: 0   },
    { t: 0.20, tx: -14, ty: -38, rot: -220, s: 1.08, b: 0.7 },
    { t: 0.45, tx: 10,  ty: -62, rot: -420, s: 1.15, b: 0.7 },
    { t: 0.70, tx: -6,  ty: -22, rot: -600, s: 1.05, b: 0.3 },
    { t: 0.90, tx: 2,   ty: -4,  rot: -700, s: 0.97, b: 0   },
    { t: 1.00, tx: 0,   ty: 0,   rot: -720, s: 1.00, b: 0   },
  ];
  const diceTransformAt = (t: number) => {
    if (t <= 0) return DICE_KEYFRAMES[0];
    if (t >= 1) return DICE_KEYFRAMES[DICE_KEYFRAMES.length - 1];
    for (let i = 0; i < DICE_KEYFRAMES.length - 1; i++) {
      const a = DICE_KEYFRAMES[i], b = DICE_KEYFRAMES[i + 1];
      if (t >= a.t && t <= b.t) {
        const u = (t - a.t) / (b.t - a.t);
        return {
          t,
          tx: a.tx + (b.tx - a.tx) * u,
          ty: a.ty + (b.ty - a.ty) * u,
          rot: a.rot + (b.rot - a.rot) * u,
          s: a.s + (b.s - a.s) * u,
          b: a.b + (b.b - a.b) * u,
        };
      }
    }
    return DICE_KEYFRAMES[DICE_KEYFRAMES.length - 1];
  };

  const loadDiceImage = (value: DiceValue, color: DiceColor): Promise<HTMLImageElement> => {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = getDiceSrc(value, color);
    });
  };

  // CSS-rendered viewport / dice sizes — used to scale the animation faithfully on canvas
  const DICE_CSS_VIEWPORT_PX = 234;  // 14.6rem
  const DICE_CSS_SIZE_PX = 73;       // 4.55rem (the displayed dice)

  /**
   * @param staticPose if true: no roll transform (dice centered, no motion).
   * Used for PNG export so the dice fills the frame.
   */
  // CSS `dice-vibrate` keyframes — used by recording handlers
  const DICE_VIBRATE_KF = [
    { t: 0.0,  tx: 0,     ty: 0,     rot: 0     },
    { t: 0.1,  tx: -1.95, ty: 0.65,  rot: -1.95 },
    { t: 0.2,  tx: 1.95,  ty: -0.65, rot: 1.95  },
    { t: 0.3,  tx: -1.95, ty: -0.65, rot: -1.3  },
    { t: 0.4,  tx: 1.95,  ty: 0.65,  rot: 1.3   },
    { t: 0.5,  tx: -1.3,  ty: 1.3,   rot: -1.95 },
    { t: 0.6,  tx: 1.3,   ty: -1.3,  rot: 1.95  },
    { t: 0.7,  tx: -1.95, ty: 0,     rot: -1.3  },
    { t: 0.8,  tx: 1.95,  ty: 0.65,  rot: 1.3   },
    { t: 0.9,  tx: -0.65, ty: -1.3,  rot: -1.3  },
    { t: 1.0,  tx: 0,     ty: 0,     rot: 0     },
  ];
  const vibrateTransformAt = (t: number) => {
    const c = ((t % 1) + 1) % 1; // wrap to [0,1)
    for (let i = 0; i < DICE_VIBRATE_KF.length - 1; i++) {
      const a = DICE_VIBRATE_KF[i], b = DICE_VIBRATE_KF[i + 1];
      if (c >= a.t && c <= b.t) {
        const u = (c - a.t) / (b.t - a.t);
        return {
          tx: a.tx + (b.tx - a.tx) * u,
          ty: a.ty + (b.ty - a.ty) * u,
          rot: a.rot + (b.rot - a.rot) * u,
        };
      }
    }
    return { tx: 0, ty: 0, rot: 0 };
  };

  const drawDiceVibrateAt = (ctx: CanvasRenderingContext2D, img: HTMLImageElement, t: number, bgColor?: string) => {
    const cw = ctx.canvas.width, ch = ctx.canvas.height;
    const cssScale = cw / DICE_CSS_VIEWPORT_PX;
    const diceSize = DICE_CSS_SIZE_PX * cssScale;
    const tr = vibrateTransformAt(t);
    if (bgColor) {
      ctx.fillStyle = bgColor;
      ctx.fillRect(0, 0, cw, ch);
    } else {
      ctx.clearRect(0, 0, cw, ch);
    }
    ctx.save();
    ctx.translate(cw / 2 + tr.tx * cssScale, ch / 2 + tr.ty * cssScale);
    ctx.rotate((tr.rot * Math.PI) / 180);
    ctx.drawImage(img, -diceSize / 2, -diceSize / 2, diceSize, diceSize);
    ctx.restore();
  };

  const drawDiceAt = (ctx: CanvasRenderingContext2D, img: HTMLImageElement, t: number, staticPose = false, bgColor?: string) => {
    const cw = ctx.canvas.width, ch = ctx.canvas.height;
    if (bgColor) {
      ctx.fillStyle = bgColor;
      ctx.fillRect(0, 0, cw, ch);
    } else {
      ctx.clearRect(0, 0, cw, ch);
    }
    if (staticPose) {
      const sz = Math.min(cw, ch) * 0.7;
      ctx.drawImage(img, (cw - sz) / 2, (ch - sz) / 2, sz, sz);
      return;
    }
    // Animated frame: scale CSS positions/sizes proportionally to canvas
    const cssScale = cw / DICE_CSS_VIEWPORT_PX;
    const diceSize = DICE_CSS_SIZE_PX * cssScale;
    const tr = diceTransformAt(t);
    ctx.save();
    ctx.translate(cw / 2 + tr.tx * cssScale, ch / 2 + tr.ty * cssScale);
    ctx.rotate((tr.rot * Math.PI) / 180);
    ctx.scale(tr.s, tr.s);
    if (tr.b > 0) ctx.filter = `blur(${tr.b * cssScale}px)`;
    ctx.drawImage(img, -diceSize / 2, -diceSize / 2, diceSize, diceSize);
    ctx.restore();
  };

  const handleDicePng = async () => {
    const img = await loadDiceImage(diceValue, diceColor);
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 1024;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    drawDiceAt(ctx, img, 0, true /* staticPose */);
    const blob: Blob | null = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    if (!blob) return;
    await saveBlob(blob, 'png', 'dice');
  };

  const handleDiceGif = async () => {
    if (isRecordingGif || isRecordingMp4) return;
    setIsRecordingGif(true);
    setRecordingProgress(0);
    try {
      const img = await loadDiceImage(diceValue, diceColor);
      const workerCode = await fetch('https://cdnjs.cloudflare.com/ajax/libs/gif.js/0.2.0/gif.worker.js').then(r => r.text());
      const workerBlob = new Blob([workerCode], { type: 'application/javascript' });
      const workerUrl = URL.createObjectURL(workerBlob);
      const W = 200, H = 200;
      const gif = new GIF({ workers: 2, quality: 10, width: W, height: H, transparent: 0x00ff00, workerScript: workerUrl });

      const totalDuration = 500;
      const fps = 30;
      const frameInterval = 1000 / fps;
      const framesCount = Math.round((totalDuration / 1000) * fps);

      const canvas = document.createElement('canvas');
      canvas.width = W;
      canvas.height = H;
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      if (!ctx) return;

      for (let i = 0; i < framesCount; i++) {
        const t = i / (framesCount - 1);
        drawDiceAt(ctx, img, t, false, '#00ff00');
        gif.addFrame(ctx.canvas, { copy: true, delay: frameInterval });
        setRecordingProgress(Math.round(((i + 1) / framesCount) * 100));
        await new Promise(r => setTimeout(r, 5));
      }

      gif.on('finished', async (blob: Blob) => {
        stashRecording('dice', 'gif', blob);
        await saveBlob(blob, 'gif', 'dice', 'lancer');
        setIsRecordingGif(false);
        setRecordingProgress(0);
        URL.revokeObjectURL(workerUrl);
      });
      gif.render();
    } catch (e) {
      console.error('Dice GIF failed', e);
      setIsRecordingGif(false);
    }
  };

  // Vibrate recording: 1.5s = ~8.3 cycles of 0.18s
  const VIBRATE_RECORD_DURATION_MS = 1500;
  const VIBRATE_CYCLE_MS = 180;

  const handleDiceVibrateGif = async () => {
    if (isRecordingGif || isRecordingMp4) return;
    setIsRecordingGif(true);
    setRecordingProgress(0);
    try {
      const img = await loadDiceImage(diceValue, diceColor);
      const workerCode = await fetch('https://cdnjs.cloudflare.com/ajax/libs/gif.js/0.2.0/gif.worker.js').then(r => r.text());
      const workerBlob = new Blob([workerCode], { type: 'application/javascript' });
      const workerUrl = URL.createObjectURL(workerBlob);
      const W = 200, H = 200;
      const gif = new GIF({ workers: 2, quality: 10, width: W, height: H, transparent: 0x00ff00, workerScript: workerUrl });
      const fps = 30;
      const frameInterval = 1000 / fps;
      const framesCount = Math.round((VIBRATE_RECORD_DURATION_MS / 1000) * fps);
      const canvas = document.createElement('canvas');
      canvas.width = W;
      canvas.height = H;
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      if (!ctx) return;
      for (let i = 0; i < framesCount; i++) {
        const tMs = i * frameInterval;
        const cycleT = (tMs % VIBRATE_CYCLE_MS) / VIBRATE_CYCLE_MS;
        drawDiceVibrateAt(ctx, img, cycleT, '#00ff00');
        gif.addFrame(ctx.canvas, { copy: true, delay: frameInterval });
        setRecordingProgress(Math.round(((i + 1) / framesCount) * 100));
        await new Promise(r => setTimeout(r, 5));
      }
      gif.on('finished', async (blob: Blob) => {
        stashRecording('dice', 'gif', blob);
        await saveBlob(blob, 'gif', 'dice', 'vibrer');
        setIsRecordingGif(false);
        setRecordingProgress(0);
        URL.revokeObjectURL(workerUrl);
      });
      gif.render();
    } catch (e) {
      console.error('Dice vibrate GIF failed', e);
      setIsRecordingGif(false);
    }
  };

  const handleDiceVibrateWebm = async () => {
    if (isRecordingGif || isRecordingMp4) return;
    setIsRecordingMp4(true);
    setRecordingProgress(0);
    const img = await loadDiceImage(diceValue, diceColor);
    const canvas = document.createElement('canvas');
    canvas.width = 200;
    canvas.height = 200;
    canvas.style.position = 'fixed';
    canvas.style.left = '-9999px';
    canvas.style.top = '-9999px';
    canvas.style.opacity = '0';
    document.body.appendChild(canvas);
    const ctx = canvas.getContext('2d');
    if (!ctx) { document.body.removeChild(canvas); return; }
    drawDiceVibrateAt(ctx, img, 0);
    const stream = canvas.captureStream(30);
    const mimeType = MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
      ? 'video/webm;codecs=vp9'
      : MediaRecorder.isTypeSupported('video/webm;codecs=vp8')
        ? 'video/webm;codecs=vp8'
        : 'video/webm';
    const mediaRecorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond: 4_000_000 });
    const chunks: Blob[] = [];
    mediaRecorder.ondataavailable = (e) => { if (e.data && e.data.size > 0) chunks.push(e.data); };
    mediaRecorder.onstop = async () => {
      const blob = new Blob(chunks, { type: 'video/webm' });
      document.body.removeChild(canvas);
      stashRecording('dice', 'webm', blob);
      await saveBlob(blob, 'webm', 'dice', 'vibrer');
      setIsRecordingMp4(false);
      setRecordingProgress(0);
    };
    mediaRecorder.start(100);
    const fps = 30;
    const framesCount = Math.round((VIBRATE_RECORD_DURATION_MS / 1000) * fps);
    for (let i = 0; i < framesCount; i++) {
      const tMs = i * (1000 / fps);
      const cycleT = (tMs % VIBRATE_CYCLE_MS) / VIBRATE_CYCLE_MS;
      drawDiceVibrateAt(ctx, img, cycleT);
      setRecordingProgress(Math.round(((i + 1) / framesCount) * 100));
      await new Promise(r => setTimeout(r, 1000 / fps));
    }
    await new Promise(r => setTimeout(r, 200));
    mediaRecorder.stop();
  };

  const handleDiceWebm = async () => {
    if (isRecordingGif || isRecordingMp4) return;
    setIsRecordingMp4(true);
    setRecordingProgress(0);
    const img = await loadDiceImage(diceValue, diceColor);
    const canvas = document.createElement('canvas');
    canvas.width = 200;
    canvas.height = 200;
    canvas.style.position = 'fixed';
    canvas.style.left = '-9999px';
    canvas.style.top = '-9999px';
    canvas.style.opacity = '0';
    document.body.appendChild(canvas);
    const ctx = canvas.getContext('2d');
    if (!ctx) { document.body.removeChild(canvas); return; }
    drawDiceAt(ctx, img, 0);
    const stream = canvas.captureStream(30);
    const mimeType = MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
      ? 'video/webm;codecs=vp9'
      : MediaRecorder.isTypeSupported('video/webm;codecs=vp8')
        ? 'video/webm;codecs=vp8'
        : 'video/webm';
    const mediaRecorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond: 4_000_000 });
    const chunks: Blob[] = [];
    mediaRecorder.ondataavailable = (e) => { if (e.data && e.data.size > 0) chunks.push(e.data); };
    mediaRecorder.onstop = async () => {
      const blob = new Blob(chunks, { type: 'video/webm' });
      document.body.removeChild(canvas);
      stashRecording('dice', 'webm', blob);
      await saveBlob(blob, 'webm', 'dice', 'lancer');
      setIsRecordingMp4(false);
      setRecordingProgress(0);
    };
    mediaRecorder.start(100);
    const duration = 500;
    const fps = 30;
    const framesCount = Math.round((duration / 1000) * fps);
    for (let i = 0; i < framesCount; i++) {
      const t = i / (framesCount - 1);
      drawDiceAt(ctx, img, t);
      setRecordingProgress(Math.round(((i + 1) / framesCount) * 100));
      await new Promise(r => setTimeout(r, 1000 / fps));
    }
    await new Promise(r => setTimeout(r, 200));
    mediaRecorder.stop();
  };

  return (
    <div className="min-h-screen bg-slate-100 font-sans text-slate-800 flex flex-col items-center">
      <header className="w-full bg-white border-b border-slate-200 p-4 shadow-sm flex items-center justify-between sticky top-0 z-50">
        <div className="flex items-center gap-4 flex-1 min-w-0">
          <div className="flex items-center gap-2 shrink-0">
          <div className="bg-blue-600 p-2 rounded-lg text-white">
            <MapPin size={24} />
          </div>
          <h1 className="text-xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-blue-600 to-indigo-600">
            Studio Animations LudoPoly
          </h1>
          <div className="flex gap-1 ml-3">
            {([
              { id: 'tokens' as const, label: 'Jetons' },
              { id: 'dice' as const, label: 'Dés' },
            ]).map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-4 py-1.5 text-sm font-bold rounded-lg transition-colors ${
                  activeTab === tab.id
                    ? 'bg-blue-600 text-white shadow-sm'
                    : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>
          </div>
          {infoMessage && (
            <div className="px-3 py-2 rounded-md bg-green-500/20 border border-green-500/40 text-green-800 text-sm font-medium truncate flex-1 min-w-0" title={infoMessage}>
              {infoMessage}
            </div>
          )}
        </div>
        <div className="flex items-center gap-3">
          <button onClick={handleReset} className="p-2 text-slate-500 hover:text-red-500 hover:bg-red-50 rounded-full transition-colors" title="Reset State">
            <RotateCcw size={20} />
          </button>
          <button onClick={handleShare} className="flex items-center gap-2 px-3 py-1.5 bg-slate-100 hover:bg-blue-50 hover:text-blue-600 rounded-full text-sm font-medium transition-colors">
            {showShareToast ? <Check size={16} className="text-green-600"/> : <Share2 size={16} />}
            {showShareToast ? "Lien Copié" : "Partager"}
          </button>
        </div>
      </header>
      <main className="flex-1 w-full max-w-none px-[100px] py-6 flex flex-col gap-6">
        {activeTab === 'tokens' && (
        <>
        <div className="flex gap-6 items-center justify-center">
          {/* LEFT column: settings dropdowns */}
          <div className="flex flex-col gap-3 shrink-0">
            <div className="flex flex-col gap-1">
              <span className="text-[10px] uppercase tracking-widest text-slate-400 font-bold ml-1">Personnage</span>
              <div className="flex items-center gap-2 bg-slate-50 p-1.5 rounded-lg border border-slate-200">
                <User size={16} className="text-slate-400 ml-2" />
                <select value={characterType} onChange={(e) => handleCharacterChange(e.target.value as CharacterType)} className="bg-transparent text-sm font-semibold text-slate-700 focus:outline-none cursor-pointer">
                  <option value="standard">Standard</option>
                  <option value="batman">Batman</option>
                  <option value="invincible">Invincible</option>
                  <option value="injured">Blessé</option>
                  <option value="sleeper">Dormeur</option>
                  <option value="none">Aucun</option>
                </select>
              </div>
            </div>
            <div className="flex flex-col gap-1">
              <span className="text-[10px] uppercase tracking-widest text-slate-400 font-bold ml-1">Couleur</span>
              <div className="flex items-center gap-2 bg-slate-50 p-1.5 rounded-lg border border-slate-200">
                <Palette size={16} className="text-slate-400 ml-2" />
                <select value={spriteColor} onChange={(e) => setSpriteColor(e.target.value)} className="bg-transparent text-sm font-semibold text-slate-700 focus:outline-none cursor-pointer">
                  <option value="blue">Bleu</option>
                  <option value="red">Rouge vif</option>
                  <option value="green">Vert</option>
                  <option value="yellow">Jaune</option>
                  <option value="orange">Orange</option>
                  <option value="purple">Violet</option>
                </select>
              </div>
            </div>
            <div className="flex flex-col gap-1">
              <span className="text-[10px] uppercase tracking-widest text-slate-400 font-bold ml-1">Fond</span>
              <div className="flex items-center gap-2 bg-slate-50 p-1.5 rounded-lg border border-slate-200">
                <ImageIcon size={16} className="text-slate-400 ml-2" />
                <select value={mainBg} onChange={(e) => setMainBg(e.target.value)} className="bg-transparent text-sm font-semibold text-slate-700 focus:outline-none cursor-pointer">
                  <option value="vert">Vert Ludo</option>
                  <option value="blanc">Blanc</option>
                  <option value="noir">Noir</option>
                  <option value="transparent">Transparent</option>
                </select>
              </div>
            </div>
            <div className="flex flex-col gap-1">
              <span className="text-[10px] uppercase tracking-widest text-slate-400 font-bold ml-1">Sélectionné</span>
              <div className="flex items-center gap-2 bg-slate-50 p-1.5 rounded-lg border border-slate-200">
                <Sparkles size={16} className="text-slate-400 ml-2" />
                <select value={selector} onChange={(e) => setSelector(e.target.value as SelectorKind)} className="bg-transparent text-sm font-semibold text-slate-700 focus:outline-none cursor-pointer">
                  <option value="none">Aucun</option>
                  <option value="halo">Halo doré</option>
                  <option value="spotlight">Projecteur</option>
                  <option value="chevron">Chevron</option>
                </select>
              </div>
            </div>
          </div>

        <div className="flex flex-col gap-3 items-center">
        {/* Support + Zoom bar above the token viewport */}
        <div className="flex items-end gap-3">
          <div className="flex flex-col gap-1">
            <span className="text-[10px] uppercase tracking-widest text-slate-400 font-bold ml-1">Support</span>
            <select
              value={support}
              onChange={(e) => setSupport(e.target.value as Support)}
              className="bg-slate-50 border border-slate-200 rounded-lg px-3 py-1.5 text-sm font-semibold text-slate-700 focus:outline-none cursor-pointer"
            >
              {(Object.keys(SUPPORT_LABEL) as Support[]).map(s => (
                <option key={s} value={s}>{SUPPORT_LABEL[s]}</option>
              ))}
            </select>
          </div>
          <div className="flex items-center gap-1 bg-slate-50 border border-slate-200 rounded-lg p-1">
            <button onClick={() => setZoom(z => Math.max(0.3, +(z - 0.1).toFixed(2)))} className="w-7 h-7 flex items-center justify-center bg-white hover:bg-slate-100 rounded text-slate-700 text-base font-bold" title="Zoom -">−</button>
            <span className="text-xs font-semibold text-slate-600 min-w-[3rem] text-center">{Math.round(totalScale * 100)}%</span>
            <button onClick={() => setZoom(z => Math.min(3, +(z + 0.1).toFixed(2)))} className="w-7 h-7 flex items-center justify-center bg-white hover:bg-slate-100 rounded text-slate-700 text-base font-bold" title="Zoom +">+</button>
          </div>
        </div>
        <section className={`flex items-center justify-center min-h-[280px] w-[22.4rem] max-w-[22.4rem] rounded-3xl transition-all duration-500 relative overflow-hidden ${MAIN_BG_OPTIONS[mainBg]}${mainBg === 'vert' ? ' border-8 border-white/10 shadow-inner' : ''}`}>
          {mainBg === 'vert' && (
            <div className="absolute inset-0 opacity-10 pointer-events-none" style={{ backgroundImage: 'radial-gradient(circle at 2px 2px, white 1px, transparent 0)', backgroundSize: '40px 40px' }} />
          )}

          <div className="relative group">
              <div className={`absolute top-3/4 left-1/2 -translate-x-1/2 w-64 h-16 rounded-[100%] blur-2xl -z-10 ${mainBg === 'vert' ? 'bg-black/30' : 'bg-black/10'}`}></div>
              {selector !== 'none' && (
                <img
                  src={SELECTOR_SRC[selector]}
                  alt="Sélecteur"
                  className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 pointer-events-none select-none -z-0"
                  style={{ width: `${110 * totalScale}px`, height: `${110 * totalScale}px` }}
                />
              )}
<div id="studio-sprite" className="transition-transform duration-500 relative z-10" style={{ transform: `scale(${1.5 * totalScale})` }}>
                {characterType !== 'none' && (
                  <TokenCharacter
                    emotion={currentEmotion}
                    characterType={characterType}
                    visualEmotion={isActionEmotion(currentEmotion) ? lastStaticEmotion : currentEmotion}
                    isTransitioning={isTransitioning}
                    color={spriteColor}
                    animationKey={animationKey}
                    isLooping={isLooping}
                    idleVariant={idleVariant}
                    joyVariant={joyVariant}
                    variants={variants}
                  />
                )}
              </div>
            </div>
        </section>

          {/* Loop + Tout jouer below the token viewport */}
          <div className="flex gap-2 items-center">
            <button
              onClick={() => handleEmotion(currentEmotion)}
              className="text-sm font-bold text-slate-700 px-3 py-1.5 bg-slate-50 hover:bg-slate-100 border border-slate-200 rounded-lg transition-colors cursor-pointer"
              title="Cliquer pour rejouer cette animation"
            >
              {EMOTION_LABELS[currentEmotion] || currentEmotion} #{getVariant(currentEmotion)}
            </button>
            <button
              onClick={() => setIsLooping(l => !l)}
              className={`flex items-center justify-center gap-1.5 text-sm font-bold px-4 py-2 rounded-lg transition-all ${isLooping ? 'bg-blue-600 text-white hover:bg-blue-700 shadow-sm' : 'bg-slate-100 text-slate-500 hover:bg-slate-200'}`}
              title="Rejouer en boucle l'animation sélectionnée"
            >
              <RotateCcw size={15} className={isLooping ? 'animate-spin' : ''} style={isLooping ? { animationDuration: '2s' } : undefined} />
              Boucle
            </button>
            <button
              onClick={playDemo}
              disabled={characterType === 'sleeper'}
              className={`flex items-center justify-center gap-2 text-sm font-bold px-4 py-2 rounded-lg transition-colors ${characterType === 'sleeper' ? 'bg-slate-100 text-slate-400 cursor-not-allowed' : isPlayingDemo ? 'bg-red-100 hover:bg-red-200 text-red-600' : 'bg-blue-100 hover:bg-blue-200 text-blue-700'}`}
            >
              {isPlayingDemo ? <X size={15} /> : <PlayCircle size={15} />}
              {isPlayingDemo ? 'Stop' : 'Tout jouer'}
            </button>
          </div>
        </div>

          {/* RIGHT column: export buttons + per-type Ouvrir */}
          <div className="flex flex-col gap-2 shrink-0">
            {(isRecordingGif || isRecordingMp4) ? (
              <div className="flex flex-col items-center px-2 py-3 gap-1 bg-white border border-slate-200 rounded-lg shadow-sm min-w-[200px]">
                <div className="w-full h-1.5 bg-slate-200 rounded-full overflow-hidden">
                  <div className="h-full bg-red-500 transition-all" style={{ width: `${recordingProgress}%` }} />
                </div>
                <span className="text-[10px] font-bold text-red-600 animate-pulse">{recordingProgress}%</span>
              </div>
            ) : (
              <>
                <div className="flex gap-2">
                  <button onClick={handleDownloadPng} className="flex items-center justify-center gap-2 px-3 py-2 bg-blue-100 hover:bg-blue-200 text-blue-700 rounded-lg text-sm font-bold transition-colors min-w-[100px]">
                    <Download size={15} /> PNG
                  </button>
                  <button onClick={() => openFilePicker('tokens', 'png')} className="flex items-center justify-center gap-1 px-2 py-2 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-lg text-xs font-bold transition-colors" title="Ouvrir un PNG existant">
                    <ImageIcon size={13} /> Ouvrir
                  </button>
                </div>
                <div className="flex gap-2">
                  <button
                    onClick={() => { if (isLooping) setIsLooping(false); setArmedRec(r => r === 'gif' ? 'none' : 'gif'); }}
                    className={`flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-sm font-bold transition-colors min-w-[100px] ${armedRec === 'gif' ? 'bg-red-600 text-white hover:bg-red-700 ring-2 ring-red-300' : 'bg-red-100 hover:bg-red-200 text-red-600'}`}
                    title="Cliquer puis sélectionner une émotion à enregistrer"
                  >
                    <Video size={15} /> {armedRec === 'gif' ? 'Choisir…' : 'GIF'}
                  </button>
                  <button onClick={() => openFilePicker('tokens', 'gif')} className="flex items-center justify-center gap-1 px-2 py-2 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-lg text-xs font-bold transition-colors" title="Ouvrir un GIF existant">
                    <ImageIcon size={13} /> Ouvrir
                  </button>
                  {lastTokenRec?.type === 'gif' && (
                    <button
                      onClick={() => setPreviewOpen('tokens')}
                      className="flex items-center justify-center gap-1 px-2 py-2 bg-green-100 hover:bg-green-200 text-green-700 rounded-lg text-xs font-bold transition-colors"
                      title="Rejouer le dernier GIF"
                    >
                      <PlayCircle size={13} /> Jouer Dernière
                    </button>
                  )}
                </div>
                <div className="flex gap-2">
                  <button
                    onClick={() => { if (isLooping) setIsLooping(false); setArmedRec(r => r === 'webm' ? 'none' : 'webm'); }}
                    className={`flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-sm font-bold transition-colors min-w-[100px] ${armedRec === 'webm' ? 'bg-orange-600 text-white hover:bg-orange-700 ring-2 ring-orange-300' : 'bg-orange-100 hover:bg-orange-200 text-orange-600'}`}
                    title="Cliquer puis sélectionner une émotion à enregistrer"
                  >
                    <Film size={15} /> {armedRec === 'webm' ? 'Choisir…' : 'WEBM'}
                  </button>
                  <button onClick={() => openFilePicker('tokens', 'webm')} className="flex items-center justify-center gap-1 px-2 py-2 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-lg text-xs font-bold transition-colors" title="Ouvrir un WEBM existant">
                    <ImageIcon size={13} /> Ouvrir
                  </button>
                  {lastTokenRec?.type === 'webm' && (
                    <button
                      onClick={() => setPreviewOpen('tokens')}
                      className="flex items-center justify-center gap-1 px-2 py-2 bg-green-100 hover:bg-green-200 text-green-700 rounded-lg text-xs font-bold transition-colors"
                      title="Rejouer le dernier WEBM"
                    >
                      <PlayCircle size={13} /> Jouer Dernière
                    </button>
                  )}
                </div>
              </>
            )}

            {/* Nomenclature reference thumbnail — under WEBM Ouvrir, hover to zoom */}
            <div
              className="relative mt-2"
              onMouseEnter={() => setNomZoom(true)}
              onMouseLeave={() => setNomZoom(false)}
            >
              <img
                src={tokenNomenclatureUrl}
                alt="Token Nomenclature"
                className="h-20 w-auto object-contain rounded-lg border border-slate-200 bg-white p-1 cursor-zoom-in"
              />
              {nomZoom && (
                <img
                  src={tokenNomenclatureUrl}
                  alt=""
                  className="fixed z-50 rounded-xl border border-slate-200 bg-white p-2 shadow-2xl pointer-events-none"
                  style={{
                    top: '50%',
                    left: '50%',
                    transform: 'translate(-50%, -50%)',
                    maxWidth: '90vw',
                    maxHeight: '90vh',
                    width: 'auto',
                    height: 'auto',
                  }}
                />
              )}
            </div>

          </div>

          {/* Génération container */}
          <div className="flex flex-col gap-2 shrink-0 w-[260px] bg-slate-50 border border-slate-200 rounded-xl p-3">
            <div className="text-xs uppercase tracking-widest text-slate-500 font-bold mb-1">Génération</div>
            <MultiSelectChips
              label="Formats"
              options={[
                { value: 'png', label: 'PNG' },
                { value: 'gif', label: 'GIF' },
                { value: 'webm', label: 'WEBM' },
              ]}
              selected={genFormats}
              onChange={setGenFormats}
            />
            <MultiSelectChips
              label="Émotions"
              options={[
                { value: 'IDLE', label: 'Repos' },
                { value: 'JOY', label: 'Joie' },
                { value: 'LAUGH', label: 'Rire' },
                { value: 'SADNESS', label: 'Tristesse' },
                { value: 'CRY', label: 'Pleure' },
                { value: 'PAIN', label: 'Douleur' },
                { value: 'TERROR', label: 'Terreur' },
                { value: 'PUZZLED', label: 'Perplexe' },
                { value: 'IMPATIENT', label: 'Moi !' },
              ]}
              selected={genEmotions}
              onChange={setGenEmotions}
            />
            <MultiSelectChips
              label="Couleurs"
              options={[
                { value: 'blue', label: 'Bleu' },
                { value: 'red', label: 'Rouge' },
                { value: 'green', label: 'Vert' },
                { value: 'yellow', label: 'Jaune' },
                { value: 'orange', label: 'Orange' },
                { value: 'purple', label: 'Violet' },
              ]}
              selected={genColors}
              onChange={setGenColors}
            />
            <MultiSelectChips
              label="Déplacements"
              options={[
                { value: 'JUMP_UP', label: 'Saut H' },
                { value: 'JUMP_DOWN', label: 'Saut B' },
                { value: 'JUMP_LEFT', label: 'Saut G' },
                { value: 'JUMP_RIGHT', label: 'Saut D' },
                { value: 'SLIDE_UP', label: 'Glis H' },
                { value: 'SLIDE_DOWN', label: 'Glis B' },
                { value: 'SLIDE_LEFT', label: 'Glis G' },
                { value: 'SLIDE_RIGHT', label: 'Glis D' },
              ]}
              selected={genMovements}
              onChange={setGenMovements}
            />
            <MultiSelectChips
              label="Variantes"
              options={[
                { value: '1', label: '1' },
                { value: '2', label: '2' },
                { value: '3', label: '3' },
                { value: '4', label: '4' },
                { value: '5', label: '5' },
              ]}
              selected={genVariants}
              onChange={setGenVariants}
            />
            {genBusy && genProgress && (
              <div className="mt-2 space-y-1">
                <div className="text-xs font-semibold text-slate-600 text-center">
                  {genProgress.current} sur {genProgress.total}
                </div>
                <div className="w-full h-2 bg-slate-200 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-blue-600 transition-all duration-200"
                    style={{ width: `${genProgress.total > 0 ? (genProgress.current / genProgress.total) * 100 : 0}%` }}
                  />
                </div>
              </div>
            )}
            <button
              onClick={async () => {
                if (genBusy) {
                  genCancelRef.current = true;
                  return;
                }
                const allEmotions = [...genEmotions, ...genMovements];
                if (genFormats.length === 0 || allEmotions.length === 0 || genColors.length === 0 || genVariants.length === 0) {
                  alert('Sélectionne au moins un format, une émotion/déplacement, une couleur et une variante.');
                  return;
                }
                setGenBusy(true);
                try {
                  const spec: GenerateSpec = {
                    kind: 'tokens',
                    characters: [characterType],
                    colors: genColors,
                    emotions: allEmotions,
                    formats: genFormats,
                    variants: genVariants.map(v => parseInt(v, 10)),
                  };
                  await studioGenerate(spec);
                } finally {
                  setGenBusy(false);
                  setCurrentGenerating(null);
                  setGenProgress(null);
                }
              }}
              className={`mt-2 px-3 py-2 rounded-lg text-sm font-bold transition-colors ${genBusy ? 'bg-red-600 text-white hover:bg-red-700' : 'bg-blue-600 text-white hover:bg-blue-700'}`}
            >
              {genBusy ? 'Stop génération' : `Générer (${genFormats.length} × ${(genEmotions.length + genMovements.length)} × ${genColors.length} × ${genVariants.length} = ${genFormats.length * (genEmotions.length + genMovements.length) * genColors.length * genVariants.length})`}
            </button>
            {currentGenerating && (
              <div className="text-[10px] font-mono text-slate-500 truncate bg-white border border-slate-200 rounded px-2 py-1" title={currentGenerating}>
                ⚙️ {currentGenerating}
              </div>
            )}
          </div>

        </div>

        <section className="bg-white rounded-2xl p-6 shadow-xl border border-slate-100">
          <div className="flex flex-row items-center gap-3 mb-6">
            <h2 className="text-sm font-bold text-slate-400 uppercase tracking-widest flex items-center gap-2">
              <span className="text-base leading-none">🤩</span> Émotions
            </h2>
          </div>
          
          <div className="grid grid-cols-3 md:grid-cols-5 lg:grid-cols-9 gap-3">
            {[
              { id: Emotion.IDLE, label: 'Repos', icon: Activity, emoji: '😐', color: 'bg-slate-100 text-slate-600 hover:bg-slate-200', durationMs: 4000 },
              { id: Emotion.JOY, label: 'Joie', icon: Smile, emoji: '😄', color: 'bg-green-100 text-green-600 hover:bg-green-200', durationMs: 1200 },
              { id: Emotion.LAUGH, label: 'Rire', icon: Smile, emoji: '😂', color: 'bg-yellow-100 text-yellow-600 hover:bg-yellow-200', durationMs: 1200 },
              { id: Emotion.SADNESS, label: 'Tristesse', icon: Meh, emoji: '😞', color: 'bg-indigo-100 text-indigo-600 hover:bg-indigo-200', durationMs: 3000 },
              { id: Emotion.CRY, label: 'Pleure', icon: Frown, emoji: '😭', color: 'bg-blue-100 text-blue-600 hover:bg-blue-200', durationMs: 2000 },
              { id: Emotion.PAIN, label: 'Douleur', icon: Zap, emoji: '🤕', color: 'bg-red-100 text-red-600 hover:bg-red-200', durationMs: 800 },
              { id: Emotion.TERROR, label: 'Terreur', icon: AlertTriangle, emoji: '😱', color: 'bg-orange-100 text-orange-600 hover:bg-orange-200', durationMs: 1000 },
              { id: Emotion.PUZZLED, label: 'Perplexe', icon: HelpCircle, emoji: '🤔', color: 'bg-teal-100 text-teal-600 hover:bg-teal-200', durationMs: 2000 },
              { id: Emotion.IMPATIENT, label: 'Moi !', icon: User, emoji: '🙋', color: 'bg-pink-100 text-pink-600 hover:bg-pink-200', durationMs: 500 },
            ].map((btn) => {
              const blocked = characterType === 'sleeper' && btn.id !== Emotion.IDLE;
              return (
                <button
                  key={btn.id}
                  onClick={() => handleEmotion(btn.id)}
                  disabled={blocked}
                  className={`flex flex-col items-center justify-center py-3 px-[5px] rounded-xl gap-2 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === btn.id ? 'ring-2 ring-offset-2 ring-blue-500 shadow-md ' + btn.color : 'opacity-70 hover:opacity-100 bg-slate-50'} ${blocked ? '!opacity-30 !cursor-not-allowed hover:!scale-100' : ''}`}
                >
                  {(btn as any).emoji ? (
                    <span className="text-xl leading-none">{(btn as any).emoji}</span>
                  ) : (
                    <btn.icon size={20} />
                  )}
                  <span className="text-xs font-bold">{btn.label}</span>
                  {btn.durationMs !== null && (
                    <span className="text-[9px] font-semibold text-slate-400 leading-none">{btn.durationMs} ms</span>
                  )}
                  <VariantBadges
                    current={getVariant(btn.id)}
                    onSelect={(n) => setVariant(btn.id, n)}
                  />
                </button>
              );
            })}
          </div>
          <hr className="my-6 border-slate-100" />
          <div className="flex flex-row items-center gap-3 mb-6">
            <h2 className="text-sm font-bold text-slate-400 uppercase tracking-widest flex items-center gap-2">
              <span className="text-base leading-none">🏃</span> Déplacements
            </h2>
          </div>
          <div className={`flex flex-wrap gap-3 ${characterType === 'sleeper' ? 'opacity-30 pointer-events-none' : ''}`}>
                <button
                    onClick={() => handleEmotion(Emotion.JUMP_UP)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.JUMP_UP ? 'ring-2 ring-offset-2 ring-sky-500 shadow-md bg-sky-100 text-sky-600' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowUp size={20} />
                    <span className="text-xs font-bold">Saut Haut</span>
                    <span className="text-[9px] font-semibold text-slate-400 leading-none">800 ms</span>
                    <VariantBadges current={getVariant(Emotion.JUMP_UP)} onSelect={(n) => setVariant(Emotion.JUMP_UP, n)} />
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.JUMP_DOWN)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.JUMP_DOWN ? 'ring-2 ring-offset-2 ring-amber-500 shadow-md bg-amber-100 text-amber-600' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowDown size={20} />
                    <span className="text-xs font-bold">Saut Bas</span>
                    <span className="text-[9px] font-semibold text-slate-400 leading-none">800 ms</span>
                    <VariantBadges current={getVariant(Emotion.JUMP_DOWN)} onSelect={(n) => setVariant(Emotion.JUMP_DOWN, n)} />
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.JUMP_LEFT)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.JUMP_LEFT ? 'ring-2 ring-offset-2 ring-purple-500 shadow-md bg-purple-100 text-purple-600' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowLeft size={20} />
                    <span className="text-xs font-bold">Saut Gauche</span>
                    <span className="text-[9px] font-semibold text-slate-400 leading-none">800 ms</span>
                    <VariantBadges current={getVariant(Emotion.JUMP_LEFT)} onSelect={(n) => setVariant(Emotion.JUMP_LEFT, n)} />
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.JUMP_RIGHT)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.JUMP_RIGHT ? 'ring-2 ring-offset-2 ring-teal-500 shadow-md bg-teal-100 text-teal-600' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowRight size={20} />
                    <span className="text-xs font-bold">Saut Droite</span>
                    <span className="text-[9px] font-semibold text-slate-400 leading-none">800 ms</span>
                    <VariantBadges current={getVariant(Emotion.JUMP_RIGHT)} onSelect={(n) => setVariant(Emotion.JUMP_RIGHT, n)} />
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.SLIDE_UP)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.SLIDE_UP ? 'ring-2 ring-offset-2 ring-slate-400 shadow-md bg-slate-200 text-slate-800' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowUp size={20} />
                    <span className="text-xs font-bold">Glisser Haut</span>
                    <span className="text-[9px] font-semibold text-slate-400 leading-none">600 ms</span>
                    <VariantBadges current={getVariant(Emotion.SLIDE_UP)} onSelect={(n) => setVariant(Emotion.SLIDE_UP, n)} />
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.SLIDE_DOWN)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.SLIDE_DOWN ? 'ring-2 ring-offset-2 ring-slate-400 shadow-md bg-slate-200 text-slate-800' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowDown size={20} />
                    <span className="text-xs font-bold">Glisser Bas</span>
                    <span className="text-[9px] font-semibold text-slate-400 leading-none">600 ms</span>
                    <VariantBadges current={getVariant(Emotion.SLIDE_DOWN)} onSelect={(n) => setVariant(Emotion.SLIDE_DOWN, n)} />
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.SLIDE_LEFT)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.SLIDE_LEFT ? 'ring-2 ring-offset-2 ring-slate-400 shadow-md bg-slate-200 text-slate-800' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowLeft size={20} />
                    <span className="text-xs font-bold">Glisser Gauche</span>
                    <span className="text-[9px] font-semibold text-slate-400 leading-none">600 ms</span>
                    <VariantBadges current={getVariant(Emotion.SLIDE_LEFT)} onSelect={(n) => setVariant(Emotion.SLIDE_LEFT, n)} />
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.SLIDE_RIGHT)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.SLIDE_RIGHT ? 'ring-2 ring-offset-2 ring-slate-400 shadow-md bg-slate-200 text-slate-800' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowRight size={20} />
                    <span className="text-xs font-bold">Glisser Droite</span>
                    <span className="text-[9px] font-semibold text-slate-400 leading-none">600 ms</span>
                    <VariantBadges current={getVariant(Emotion.SLIDE_RIGHT)} onSelect={(n) => setVariant(Emotion.SLIDE_RIGHT, n)} />
                </button>
          </div>
        </section>
        </>
        )}

        {activeTab === 'dice' && (
          <div className="flex gap-6 items-end justify-center">
            {/* LEFT column: settings dropdowns */}
            <div className="flex flex-col gap-3 shrink-0">
              <div className="flex flex-col gap-1">
                <span className="text-[10px] uppercase tracking-widest text-slate-400 font-bold ml-1">Valeur dé</span>
                <div className="flex items-center gap-2 bg-slate-50 p-1.5 rounded-lg border border-slate-200">
                  <Dices size={16} className="text-slate-400 ml-2" />
                  <select
                    value={diceValue}
                    onChange={(e) => {
                      const v = parseInt(e.target.value, 10) as DiceValue;
                      setDiceValue(v);
                      if (diceState === 'idle') setDiceDisplayValue(v);
                    }}
                    className="bg-transparent text-sm font-semibold text-slate-700 focus:outline-none cursor-pointer"
                  >
                    {[1,2,3,4,5,6].map(n => (
                      <option key={n} value={n}>{n}</option>
                    ))}
                  </select>
                </div>
              </div>
              <div className="flex flex-col gap-1">
                <span className="text-[10px] uppercase tracking-widest text-slate-400 font-bold ml-1">Couleur</span>
                <div className="flex items-center gap-2 bg-slate-50 p-1.5 rounded-lg border border-slate-200">
                  <Palette size={16} className="text-slate-400 ml-2" />
                  <select
                    value={diceColor}
                    onChange={(e) => setDiceColor(e.target.value as DiceColor)}
                    className="bg-transparent text-sm font-semibold text-slate-700 focus:outline-none cursor-pointer"
                  >
                    <option value="blue">Bleu</option>
                    <option value="red">Rouge</option>
                    <option value="green">Vert</option>
                    <option value="yellow">Jaune</option>
                    <option value="orange">Orange</option>
                    <option value="purple">Violet</option>
                    <option value="white">Blanc</option>
                  </select>
                </div>
              </div>
              <div className="flex flex-col gap-1">
                <span className="text-[10px] uppercase tracking-widest text-slate-400 font-bold ml-1">Fond</span>
                <div className="flex items-center gap-2 bg-slate-50 p-1.5 rounded-lg border border-slate-200">
                  <ImageIcon size={16} className="text-slate-400 ml-2" />
                  <select value={mainBg} onChange={(e) => setMainBg(e.target.value)} className="bg-transparent text-sm font-semibold text-slate-700 focus:outline-none cursor-pointer">
                    <option value="vert">Vert Ludo</option>
                    <option value="blanc">Blanc</option>
                    <option value="noir">Noir</option>
                    <option value="transparent">Transparent</option>
                  </select>
                </div>
              </div>
            </div>

            <div className="flex flex-col gap-3 items-center">
              {/* Support + Zoom bar above the dice viewport */}
              <div className="flex items-end gap-3">
                <div className="flex flex-col gap-1">
                  <span className="text-[10px] uppercase tracking-widest text-slate-400 font-bold ml-1">Support</span>
                  <select
                    value={support}
                    onChange={(e) => setSupport(e.target.value as Support)}
                    className="bg-slate-50 border border-slate-200 rounded-lg px-3 py-1.5 text-sm font-semibold text-slate-700 focus:outline-none cursor-pointer"
                  >
                    {(Object.keys(SUPPORT_LABEL) as Support[]).map(s => (
                      <option key={s} value={s}>{SUPPORT_LABEL[s]}</option>
                    ))}
                  </select>
                </div>
                <div className="flex items-center gap-1 bg-slate-50 border border-slate-200 rounded-lg p-1">
                  <button onClick={() => setZoom(z => Math.max(0.3, +(z - 0.1).toFixed(2)))} className="w-7 h-7 flex items-center justify-center bg-white hover:bg-slate-100 rounded text-slate-700 text-base font-bold" title="Zoom -">−</button>
                  <span className="text-xs font-semibold text-slate-600 min-w-[3rem] text-center">{Math.round(totalScale * 100)}%</span>
                  <button onClick={() => setZoom(z => Math.min(3, +(z + 0.1).toFixed(2)))} className="w-7 h-7 flex items-center justify-center bg-white hover:bg-slate-100 rounded text-slate-700 text-base font-bold" title="Zoom +">+</button>
                </div>
              </div>
              <section className={`flex items-end justify-center min-h-[237px] w-[14.6rem] max-w-[14.6rem] pb-[55px] rounded-3xl transition-all duration-500 relative overflow-hidden ${MAIN_BG_OPTIONS[mainBg]}${mainBg === 'vert' ? ' border-8 border-white/10 shadow-inner' : ''}`}>
                {mainBg === 'vert' && (
                  <div className="absolute inset-0 opacity-10 pointer-events-none" style={{ backgroundImage: 'radial-gradient(circle at 2px 2px, white 1px, transparent 0)', backgroundSize: '40px 40px' }} />
                )}
                <div className="relative group">
                  <div className={`absolute top-3/4 left-1/2 -translate-x-1/2 w-20 h-5 rounded-[100%] blur-2xl -z-10 ${mainBg === 'vert' ? 'bg-black/30' : 'bg-black/10'}`}></div>
                  <img
                    key={diceRollKey}
                    src={getDiceSrc(diceDisplayValue, diceColor)}
                    alt={`Dé ${diceDisplayValue} ${diceColor}`}
                    style={{ width: `${4.55 * totalScale}rem`, height: `${4.55 * totalScale}rem` }}
                  className={`object-contain drop-shadow-lg select-none ${
                    diceState === 'rolling'
                      ? (getVariant('DICE_LANCER') === 1 ? 'animate-dice-roll' : `animate-dice-roll-${getVariant('DICE_LANCER')}`)
                      : diceState === 'vibrating'
                        ? (getVariant('DICE_VIBRER') === 1 ? 'animate-dice-vibrate' : `animate-dice-vibrate-${getVariant('DICE_VIBRER')}`)
                        : ''
                  }`}
                  />
                </div>
              </section>

              {/* Lancer + Vibrer + Boucle buttons below the viewport */}
              <div className="flex gap-2">
                <button
                  onClick={rollDice}
                  className={`flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-sm font-bold transition-colors ${armedDiceRec !== 'none' ? 'bg-yellow-200 text-yellow-800 ring-2 ring-yellow-500 hover:bg-yellow-300' : 'bg-orange-100 hover:bg-orange-200 text-orange-600'}`}
                >
                  <div className="flex flex-col items-center leading-none">
                    <span className="flex items-center gap-2"><RotateCcw size={15} /> Lancer</span>
                    <span className="text-[9px] font-semibold opacity-70 mt-0.5">500 ms</span>
                    <VariantBadges current={getVariant('DICE_LANCER')} onSelect={(n) => setVariant('DICE_LANCER', n)} />
                  </div>
                </button>
                <button
                  onClick={() => {
                    const armed = armedDiceRec;
                    if (armed !== 'none') {
                      setArmedDiceRec('none');
                      if (armed === 'gif') { handleDiceVibrateGif(); return; }
                      if (armed === 'webm') { handleDiceVibrateWebm(); return; }
                    }
                    setLastDiceAnim('vibrer');
                    lastDiceAnimRef.current = 'vibrer';
                    // Cancel any ongoing roll cleanly so we can switch to vibrate
                    clearDiceTimers();
                    diceRollingRef.current = false;
                    if (diceState === 'vibrating') {
                      setDiceState('idle');
                      return;
                    }
                    setDiceState('vibrating');
                    // If not in loop mode, auto-stop after 1 cycle (180ms)
                    if (!isDiceLoopingRef.current) {
                      window.setTimeout(() => {
                        setDiceState(s => (s === 'vibrating' ? 'idle' : s));
                      }, 180);
                    }
                  }}
                  className={`flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-sm font-bold transition-colors ${diceState === 'vibrating' ? 'bg-amber-500 text-white hover:bg-amber-600' : armedDiceRec !== 'none' ? 'bg-yellow-200 text-yellow-800 ring-2 ring-yellow-500 hover:bg-yellow-300' : 'bg-amber-100 hover:bg-amber-200 text-amber-700'}`}
                  title="Faire vibrer le dé (c'est ton tour)"
                >
                  <div className="flex flex-col items-center leading-none">
                    <span className="flex items-center gap-2"><Zap size={15} /> Vibrer</span>
                    <span className="text-[9px] font-semibold opacity-70 mt-0.5">180 ms</span>
                    <VariantBadges current={getVariant('DICE_VIBRER')} onSelect={(n) => setVariant('DICE_VIBRER', n)} />
                  </div>
                </button>
                <button
                  onClick={toggleDiceLoop}
                  className={`flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-sm font-bold transition-colors ${isDiceLooping ? 'bg-blue-600 text-white hover:bg-blue-700 shadow-sm' : 'bg-slate-100 text-slate-500 hover:bg-slate-200'}`}
                  title="Lancer le dé en boucle"
                >
                  <RotateCcw size={15} className={isDiceLooping ? 'animate-spin' : ''} style={isDiceLooping ? { animationDuration: '1.5s' } : undefined} />
                  Boucle
                </button>
              </div>
            </div>

            {/* RIGHT column: export buttons + per-type Ouvrir */}
            <div className="flex flex-col gap-2 shrink-0">
              {(isRecordingGif || isRecordingMp4) ? (
                <div className="flex flex-col items-center px-2 py-3 gap-1 bg-white border border-slate-200 rounded-lg shadow-sm min-w-[200px]">
                  <div className="w-full h-1.5 bg-slate-200 rounded-full overflow-hidden">
                    <div className="h-full bg-red-500 transition-all" style={{ width: `${recordingProgress}%` }} />
                  </div>
                  <span className="text-[10px] font-bold text-red-600 animate-pulse">{recordingProgress}%</span>
                </div>
              ) : (
                <>
                  <div className="flex gap-2">
                    <button onClick={handleDicePng} className="flex items-center justify-center gap-2 px-3 py-2 bg-blue-100 hover:bg-blue-200 text-blue-700 rounded-lg text-sm font-bold transition-colors min-w-[100px]">
                      <Download size={15} /> PNG
                    </button>
                    <button onClick={() => openFilePicker('dice', 'png')} className="flex items-center justify-center gap-1 px-2 py-2 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-lg text-xs font-bold transition-colors" title="Ouvrir un PNG existant">
                      <ImageIcon size={13} /> Ouvrir
                    </button>
                  </div>
                  <div className="flex gap-2">
                    <button
                      onClick={() => { if (isDiceLooping) toggleDiceLoop(); setArmedDiceRec(r => r === 'gif' ? 'none' : 'gif'); }}
                      className={`flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-sm font-bold transition-colors min-w-[100px] ${armedDiceRec === 'gif' ? 'bg-red-600 text-white hover:bg-red-700 ring-2 ring-red-300' : 'bg-red-100 hover:bg-red-200 text-red-600'}`}
                      title="Cliquer puis Lancer ou Vibrer pour enregistrer"
                    >
                      <Video size={15} /> {armedDiceRec === 'gif' ? 'Choisir…' : 'GIF'}
                    </button>
                    <button onClick={() => openFilePicker('dice', 'gif')} className="flex items-center justify-center gap-1 px-2 py-2 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-lg text-xs font-bold transition-colors" title="Ouvrir un GIF existant">
                      <ImageIcon size={13} /> Ouvrir
                    </button>
                    {lastDiceRec?.type === 'gif' && (
                      <button
                        onClick={() => setPreviewOpen('dice')}
                        className="flex items-center justify-center gap-1 px-2 py-2 bg-green-100 hover:bg-green-200 text-green-700 rounded-lg text-xs font-bold transition-colors"
                        title="Rejouer le dernier GIF"
                      >
                        <PlayCircle size={13} /> Jouer Dernière
                      </button>
                    )}
                  </div>
                  <div className="flex gap-2">
                    <button
                      onClick={() => { if (isDiceLooping) toggleDiceLoop(); setArmedDiceRec(r => r === 'webm' ? 'none' : 'webm'); }}
                      className={`flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-sm font-bold transition-colors min-w-[100px] ${armedDiceRec === 'webm' ? 'bg-orange-600 text-white hover:bg-orange-700 ring-2 ring-orange-300' : 'bg-orange-100 hover:bg-orange-200 text-orange-600'}`}
                      title="Cliquer puis Lancer ou Vibrer pour enregistrer"
                    >
                      <Film size={15} /> {armedDiceRec === 'webm' ? 'Choisir…' : 'WEBM'}
                    </button>
                    <button onClick={() => openFilePicker('dice', 'webm')} className="flex items-center justify-center gap-1 px-2 py-2 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-lg text-xs font-bold transition-colors" title="Ouvrir un WEBM existant">
                      <ImageIcon size={13} /> Ouvrir
                    </button>
                    {lastDiceRec?.type === 'webm' && (
                      <button
                        onClick={() => setPreviewOpen('dice')}
                        className="flex items-center justify-center gap-1 px-2 py-2 bg-green-100 hover:bg-green-200 text-green-700 rounded-lg text-xs font-bold transition-colors"
                        title="Rejouer le dernier WEBM"
                      >
                        <PlayCircle size={13} /> Jouer Dernière
                      </button>
                    )}
                  </div>
                </>
              )}
            </div>
          </div>
        )}
      </main>

      {previewOpen && (() => {
        const rec = previewOpen === 'tokens' ? lastTokenRec : lastDiceRec;
        if (!rec) return null;
        return (
          <div
            className="fixed inset-0 bg-black/75 z-[100] flex items-center justify-center p-8"
            onClick={() => setPreviewOpen(null)}
          >
            <div className="relative bg-white rounded-2xl p-4 shadow-2xl max-w-[90vw] max-h-[90vh] flex flex-col items-center gap-3" onClick={(e) => e.stopPropagation()}>
              <button
                onClick={() => setPreviewOpen(null)}
                className="absolute -top-2 -right-2 bg-white rounded-full shadow-lg p-1 hover:bg-slate-100 z-10"
                aria-label="Fermer"
              >
                <X size={18} />
              </button>
              {rec.type === 'gif' ? (
                <img src={rec.url} alt="Aperçu animation" className="max-w-[80vw] max-h-[75vh] object-contain bg-slate-100 rounded" />
              ) : (
                <video src={rec.url} autoPlay loop controls className="max-w-[80vw] max-h-[75vh] bg-slate-100 rounded" />
              )}
              <span className="text-xs font-bold text-slate-500 uppercase tracking-widest">
                {previewOpen === 'tokens' ? 'Token' : 'Dé'} · {rec.type.toUpperCase()}
              </span>
            </div>
          </div>
        );
      })()}

      {filePickerOpen && (
        <div
          className="fixed inset-0 bg-black/70 z-[100] flex items-center justify-center p-8"
          onClick={() => setFilePickerOpen(null)}
        >
          <div className="relative bg-white rounded-2xl p-5 shadow-2xl max-w-[70vw] max-h-[80vh] w-[480px] flex flex-col gap-3" onClick={(e) => e.stopPropagation()}>
            <button
              onClick={() => setFilePickerOpen(null)}
              className="absolute -top-2 -right-2 bg-white rounded-full shadow-lg p-1 hover:bg-slate-100 z-10"
              aria-label="Fermer"
            >
              <X size={18} />
            </button>
            <h3 className="text-sm font-bold text-slate-700 uppercase tracking-widest">
              Ouvrir un fichier — {filePickerOpen === 'tokens' ? 'Tokens' : 'Dés'}
            </h3>
            {filePickerFiles.length === 0 ? (
              <p className="text-slate-500 text-sm py-8 text-center">Aucun fichier enregistré.</p>
            ) : (
              <ul className="overflow-y-auto max-h-[60vh] divide-y divide-slate-100">
                {filePickerFiles.map((f) => (
                  <li key={`${f.type}-${f.name}`}>
                    <button
                      onClick={() => openExternalFile(filePickerOpen, f.type, f.name)}
                      className="w-full text-left px-3 py-2 hover:bg-slate-50 flex items-center gap-3 transition-colors"
                    >
                      <span className={`text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded ${
                        f.type === 'png' ? 'bg-blue-100 text-blue-700' :
                        f.type === 'gif' ? 'bg-red-100 text-red-700' :
                        'bg-orange-100 text-orange-700'
                      }`}>
                        {f.type}
                      </span>
                      <span className="text-sm font-medium text-slate-700 truncate flex-1">{f.name}</span>
                      <span className="text-[10px] text-slate-400 shrink-0">
                        {new Date(f.mtime).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      )}

      {externalPreview && (
        <div
          className="fixed inset-0 bg-black/75 z-[100] flex items-center justify-center p-8"
          onClick={() => setExternalPreview(null)}
        >
          <div className="relative bg-white rounded-2xl p-4 shadow-2xl max-w-[90vw] max-h-[90vh] flex flex-col items-center gap-3" onClick={(e) => e.stopPropagation()}>
            <button
              onClick={() => setExternalPreview(null)}
              className="absolute -top-2 -right-2 bg-white rounded-full shadow-lg p-1 hover:bg-slate-100 z-10"
              aria-label="Fermer"
            >
              <X size={18} />
            </button>
            {externalPreview.type === 'webm' ? (
              <video src={externalPreview.url} autoPlay loop controls className="max-w-[80vw] max-h-[75vh] bg-slate-100 rounded" />
            ) : (
              <img src={externalPreview.url} alt={externalPreview.name} className="max-w-[80vw] max-h-[75vh] object-contain bg-slate-100 rounded" />
            )}
            <span className="text-xs font-bold text-slate-500 tracking-wide truncate max-w-[80vw]">
              {externalPreview.type.toUpperCase()} · {externalPreview.name}
            </span>
          </div>
        </div>
      )}
    </div>
  );
}
