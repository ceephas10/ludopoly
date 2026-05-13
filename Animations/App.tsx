import React, { useState, useEffect, useRef } from 'react';
import { TokenCharacter } from './components/TokenCharacter';

// Auto-load all 36 dice images (6 values × 6 colors)
const DICE_IMAGES = import.meta.glob('./AnimStock/Dices/Dice_*.png', { eager: true, query: '?url', import: 'default' }) as Record<string, string>;
const DICE_COLORS = ['blue', 'red', 'green', 'yellow', 'orange', 'purple'] as const;
type DiceColor = typeof DICE_COLORS[number];
type DiceValue = 1 | 2 | 3 | 4 | 5 | 6;
const getDiceSrc = (value: DiceValue, color: DiceColor): string => {
  const path = `./AnimStock/Dices/Dice_${value}_${color}.png`;
  return DICE_IMAGES[path];
};
import { Emotion, CharacterType } from './types';
import { 
  Activity, MapPin, Smile, Frown, Zap, AlertTriangle, PlayCircle, 
  Loader2, Camera, X, Save, Check, RotateCcw, Download, Video, 
  Palette, Share2, Film, ArrowRight, ArrowLeft, ArrowUp, 
  ArrowDown, Meh, HelpCircle, User, Image as ImageIcon, MoveHorizontal
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
  const [characterType, setCharacterType] = useState<CharacterType>('normal');
  const [animationKey, setAnimationKey] = useState<number>(0);
  const [activeTab, setActiveTab] = useState<'tokens' | 'dice'>('tokens');
  const [isLooping, setIsLooping] = useState<boolean>(false);
  const [diceState, setDiceState] = useState<'idle' | 'rolling'>('idle');
  const [diceRollKey, setDiceRollKey] = useState<number>(0);
  const [diceValue, setDiceValue] = useState<DiceValue>(1);
  const [diceColor, setDiceColor] = useState<DiceColor>('blue');
  const [diceDisplayValue, setDiceDisplayValue] = useState<DiceValue>(1);
  const diceFlipTimerRef = useRef<number | null>(null);
  const diceEndTimerRef = useRef<number | null>(null);
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
  };

  useEffect(() => {
    return clearDiceTimers;
  }, []);

  const rollDice = () => {
    // Prevent re-entry even if button click slips through during state lag
    if (diceRollingRef.current) return;
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
    }, 500);
  };
  const [isPlayingDemo, setIsPlayingDemo] = useState<boolean>(false);
  const [isStudioMode, setIsStudioMode] = useState<boolean>(false);
  const [studioBg, setStudioBg] = useState<string>('bg-[#00b140]');
  const [mainBg, setMainBg] = useState<string>('vert');
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
        const urlBgCode = params.get('b') || params.get('bg');
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
        if (urlChar && ['normal', 'batman', 'invincible', 'injured', 'sleeper'].includes(urlChar)) {
            setCharacterType(urlChar);
            hasUrlParams = true;
        }
        if (urlMainBg && MAIN_BG_OPTIONS[urlMainBg]) {
            setMainBg(urlMainBg);
            hasUrlParams = true;
        }
        if (urlBgCode) {
            const mappedBg = BG_MAP[urlBgCode] || urlBgCode;
            setStudioBg(mappedBg);
            setIsStudioMode(true);
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
        if (parsed.bg) setStudioBg(parsed.bg);
        if (parsed.mainBg) setMainBg(parsed.mainBg);
        if (parsed.color) setSpriteColor(parsed.color);
        if (parsed.characterType) setCharacterType(parsed.characterType);
      } catch (e) {
        console.error("Failed to load saved state", e);
      }
    }
  }, []);

  const getFilename = (ext: string) => {
    const date = new Date();
    const dateStr = date.toISOString().slice(0, 10).replace(/-/g, '');
    return `${dateStr}_pawn_${characterType}_${spriteColor}_${currentEmotion.toLowerCase()}.${ext}`;
  };

  const showInfo = (msg: string) => {
    setInfoMessage(msg);
    if (infoTimerRef.current) window.clearTimeout(infoTimerRef.current);
    infoTimerRef.current = window.setTimeout(() => setInfoMessage(null), 10000);
  };

  const saveBlob = async (blob: Blob, ext: 'png' | 'gif' | 'webm') => {
    const filename = getFilename(ext);
    const res = await fetch(`/api/save?ext=${ext}&filename=${encodeURIComponent(filename)}`, {
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
    const state = { emotion: currentEmotion, bg: studioBg, mainBg, color: spriteColor, characterType };
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
    const bgCode = BG_REVERSE_MAP[studioBg] || 'green';
    params.set('b', bgCode);
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
    if (currentEmotion === newEmotion) return;
    setIsTransitioning(true);
    setTimeout(() => {
      if (!isActionEmotion(newEmotion)) setLastStaticEmotion(newEmotion);
      setCurrentEmotion(newEmotion);
      setIsTransitioning(false);
    }, 300);
  };

  const handleCharacterChange = (newType: CharacterType) => {
    setCharacterType(newType);
    if (newType === 'sleeper') {
      setCurrentEmotion(Emotion.IDLE);
      setLastStaticEmotion(Emotion.IDLE);
    }
  };

  const playDemo = async () => {
    if (isPlayingDemo) return;
    setIsPlayingDemo(true);
    const sequence = [
      Emotion.JOY, Emotion.LAUGH, Emotion.SADNESS, Emotion.CRY, 
      Emotion.PAIN, Emotion.TERROR, Emotion.PUZZLED, Emotion.IMPATIENT, Emotion.JUMP_UP, Emotion.JUMP_DOWN, Emotion.JUMP_RIGHT, Emotion.JUMP_LEFT,
      Emotion.SLIDE_UP, Emotion.SLIDE_DOWN, Emotion.SLIDE_LEFT, Emotion.SLIDE_RIGHT
    ];
    for (const emotion of sequence) {
      handleEmotion(emotion);
      await new Promise(resolve => setTimeout(resolve, 2500));
    }
    handleEmotion(Emotion.IDLE);
    setIsPlayingDemo(false);
  };

  /**
   * Promise-based frame drawing.
   * Injects animation-delay into the SVG to force internal animations to the correct time.
   */
  const drawFrame = (ctx: CanvasRenderingContext2D, centerX: number, anchorY: number, scale: number, timeOffset: number): Promise<void> => {
    return new Promise((resolve) => {
      const tokenBody = document.getElementById('token-body');
      const svgElement = document.querySelector('#studio-sprite svg');
      if (!tokenBody || !svgElement) { resolve(); return; }

      const transform = window.getComputedStyle(tokenBody).transform;
      let svgData = new XMLSerializer().serializeToString(svgElement);

      // Collect all styles
      const styleTags = document.querySelectorAll('style');
      let stylesString = '';
      styleTags.forEach(s => stylesString += s.textContent);

      // Force SVG dimensions and inject a global animation-delay to sync with record time
      svgData = svgData.replace('<svg', '<svg width="100" height="140"');
      const timeCorrectionStyle = `* { animation-delay: -${timeOffset.toFixed(3)}s !important; animation-play-state: paused !important; }`;
      svgData = svgData.replace('>', `><style>${stylesString} ${timeCorrectionStyle}</style>`);

      const img = new Image();
      const svgBlob = new Blob([svgData], { type: 'image/svg+xml;charset=utf-8' });
      const url = URL.createObjectURL(svgBlob);

      img.onload = () => {
        ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
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

  const handleRecordGif = async () => {
    if (isRecordingGif || isRecordingMp4) return;
    setIsRecordingGif(true);
    setRecordingProgress(0);

    try {
      const workerBlob = await fetch('https://cdnjs.cloudflare.com/ajax/libs/gif.js/0.2.0/gif.worker.js').then(r => r.blob());
      const workerUrl = URL.createObjectURL(workerBlob);
      const gif = new GIF({ workers: 4, quality: 10, width: 400, height: 400, transparent: null, workerScript: workerUrl });
      
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = 400;
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      if (!ctx) return;

      const totalDuration = 2000; // 2 seconds
      const fps = 20;
      const frameInterval = 1000 / fps;
      const framesCount = totalDuration / frameInterval;

      // Restart animation to ensure time synchronization
      setAnimationKey(prev => prev + 1);
      const recordStartTime = Date.now();

      for (let i = 0; i < framesCount; i++) {
        const currentTimeOffset = (i * frameInterval) / 1000;
        await drawFrame(ctx, 200, 360, 1.5, currentTimeOffset);
        gif.addFrame(ctx.canvas, { copy: true, delay: frameInterval });
        setRecordingProgress(Math.round(((i + 1) / framesCount) * 100));
        // Small yield to UI
        await new Promise(r => setTimeout(r, 5));
      }

      gif.on('finished', async (blob: Blob) => {
        await saveBlob(blob, 'gif');
        setIsRecordingGif(false);
        setRecordingProgress(0);
        URL.revokeObjectURL(workerUrl);
      });

      gif.render();
    } catch (e) {
      console.error("Recording failed", e);
      setIsRecordingGif(false);
    }
  };

  const handleRecordMp4 = async () => {
    if (isRecordingGif || isRecordingMp4) return;
    setIsRecordingMp4(true);
    setRecordingProgress(0);

    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 400;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const stream = canvas.captureStream(30);
    const mediaRecorder = new MediaRecorder(stream, { mimeType: "video/webm" });
    const chunks: Blob[] = [];

    mediaRecorder.ondataavailable = (e) => chunks.push(e.data);
    mediaRecorder.onstop = async () => {
      const blob = new Blob(chunks, { type: "video/webm" });
      await saveBlob(blob, 'webm');
      setIsRecordingMp4(false);
      setRecordingProgress(0);
    };

    mediaRecorder.start();
    setAnimationKey(prev => prev + 1);

    const duration = 2000;
    const startTime = Date.now();
    const fps = 30;

    const runRecorder = async () => {
      for (let i = 0; i < (duration / 1000) * fps; i++) {
        const timeOffset = i / fps;
        await drawFrame(ctx, 200, 360, 1.5, timeOffset);
        setRecordingProgress(Math.round((i / ((duration / 1000) * fps)) * 100));
        await new Promise(r => setTimeout(r, 1000 / fps));
      }
      mediaRecorder.stop();
    };

    runRecorder();
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

  return (
    <div className="min-h-screen bg-slate-100 font-sans text-slate-800 flex flex-col items-center">
      <header className="w-full bg-white border-b border-slate-200 p-4 shadow-sm flex items-center justify-between sticky top-0 z-50">
        <div className="flex items-center gap-4 flex-1 min-w-0">
          <div className="flex items-center gap-2 shrink-0">
          <div className="bg-blue-600 p-2 rounded-lg text-white">
            <MapPin size={24} />
          </div>
          <h1 className="text-xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-blue-600 to-indigo-600">
            LudoPoly Animations
          </h1>
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
          <button onClick={handleSaveState} className="flex items-center gap-2 px-3 py-1.5 bg-slate-100 hover:bg-slate-200 rounded-full text-sm font-medium transition-colors">
            {showSavedToast ? <Check size={16} className="text-green-600"/> : <Save size={16} />}
            {showSavedToast ? "Sauvé !" : "Sauver"}
          </button>
          <button onClick={() => { setIsStudioMode(!isStudioMode); }} className={`flex items-center gap-2 px-4 py-2 rounded-full font-semibold transition-all shadow-sm ${isStudioMode ? 'bg-red-500 text-white hover:bg-red-600' : 'bg-green-600 text-white hover:bg-green-700'}`}>
            {isStudioMode ? <X size={18} /> : <Camera size={18} />}
            {isStudioMode ? 'Quitter Studio' : 'Mode Studio'}
          </button>
        </div>
      </header>
      <main className="flex-1 w-full max-w-5xl p-6 flex flex-col gap-6">

        <div className="flex gap-2 border-b border-slate-200">
          {([
            { id: 'tokens' as const, label: 'Jetons' },
            { id: 'dice' as const, label: 'Dés' },
          ]).map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-5 py-2.5 text-sm font-bold rounded-t-lg transition-colors ${
                activeTab === tab.id
                  ? 'bg-white text-blue-600 border border-slate-200 border-b-white -mb-px'
                  : 'text-slate-500 hover:text-slate-700 hover:bg-slate-50'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {activeTab === 'tokens' && (
        <>
        <section className={`flex-1 flex items-center justify-center min-h-[400px] rounded-3xl transition-all duration-500 relative overflow-hidden ${isStudioMode ? '' : MAIN_BG_OPTIONS[mainBg] + (mainBg === 'vert' ? ' border-8 border-white/10 shadow-inner' : '')}`}>
          {!isStudioMode && mainBg === 'vert' && (
            <div className="absolute inset-0 opacity-10 pointer-events-none" style={{ backgroundImage: 'radial-gradient(circle at 2px 2px, white 1px, transparent 0)', backgroundSize: '40px 40px' }} />
          )}
          
          {isStudioMode ? (
            <div className={`relative w-full h-[500px] overflow-hidden flex items-center justify-center bg-slate-900 transition-colors`}>
              <div className="absolute top-4 right-4 z-20 flex flex-col gap-2 bg-white/90 p-2 rounded-lg backdrop-blur-sm shadow-sm">
                <p className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1 text-center">Fond</p>
                <div className="grid grid-cols-2 gap-2">
                   <button onClick={() => setStudioBg(BG_MAP['green'])} className="w-8 h-8 rounded-full bg-[#00b140] border border-slate-200 hover:scale-110 transition-transform" title="Green Screen" />
                   <button onClick={() => setStudioBg(BG_MAP['blue'])} className="w-8 h-8 rounded-full bg-[#0047bb] border border-slate-200 hover:scale-110 transition-transform" title="Blue Screen" />
                   <button onClick={() => setStudioBg(BG_MAP['white'])} className="w-8 h-8 rounded-full bg-white border border-slate-200 hover:scale-110 transition-transform" title="White" />
                   <button onClick={() => setStudioBg(BG_MAP['black'])} className="w-8 h-8 rounded-full bg-black border border-slate-600 hover:scale-110 transition-transform" title="Black" />
                </div>
                <div className="h-px bg-slate-200 my-1" />
                
                {(isRecordingGif || isRecordingMp4) ? (
                  <div className="flex flex-col items-center p-2 gap-1">
                    <div className="w-full h-1.5 bg-slate-200 rounded-full overflow-hidden">
                      <div className="h-full bg-red-500 transition-all" style={{ width: `${recordingProgress}%` }} />
                    </div>
                    <span className="text-[10px] font-bold text-red-600 animate-pulse">{recordingProgress}%</span>
                  </div>
                ) : (
                  <>
                    <button onClick={handleDownloadPng} className="flex items-center justify-center gap-2 w-full py-1.5 bg-blue-100 hover:bg-blue-200 text-blue-700 rounded text-xs font-bold transition-colors">
                      <Download size={14} /> PNG
                    </button>
                    <button onClick={handleRecordGif} className="flex items-center justify-center gap-2 w-full py-1.5 rounded text-xs font-bold transition-colors bg-red-100 hover:bg-red-200 text-red-600">
                      <Video size={14} /> GIF
                    </button>
                    <button onClick={handleRecordMp4} className="flex items-center justify-center gap-2 w-full py-1.5 rounded text-xs font-bold transition-colors bg-orange-100 hover:bg-orange-200 text-orange-600">
                      <Film size={14} /> WEBM
                    </button>
                  </>
                )}
              </div>

              <div className={`relative w-[400px] h-[400px] overflow-hidden shadow-2xl ${studioBg}`}>
                  <div className="absolute inset-0 pointer-events-none" style={{ backgroundImage: `linear-gradient(to right, rgba(128,128,128,0.2) 1px, transparent 1px), linear-gradient(to bottom, rgba(128,128,128,0.2) 1px, transparent 1px)`, backgroundSize: '20px 20px' }} />
                  <div id="studio-sprite" className="absolute left-1/2 top-[360px] -translate-x-1/2 -translate-y-[100%] scale-[1.5] origin-bottom">
                     <TokenCharacter
                        emotion={currentEmotion}
                        characterType={characterType}
                        visualEmotion={isActionEmotion(currentEmotion) ? lastStaticEmotion : currentEmotion}
                        isTransitioning={isTransitioning}
                        color={spriteColor}
                        showBoundingBox={true}
                        animationKey={animationKey}
                        isLooping={isLooping}
                     />
                  </div>
              </div>
            </div>
          ) : (
            <div className="relative group">
              <div className={`absolute top-3/4 left-1/2 -translate-x-1/2 w-64 h-16 rounded-[100%] blur-2xl -z-10 ${mainBg === 'vert' ? 'bg-black/30' : 'bg-black/10'}`}></div>
              <div className="scale-150 transition-transform duration-500">
                <TokenCharacter
                  emotion={currentEmotion}
                  characterType={characterType}
                  visualEmotion={isActionEmotion(currentEmotion) ? lastStaticEmotion : currentEmotion}
                  isTransitioning={isTransitioning}
                  color={spriteColor}
                  animationKey={animationKey}
                  isLooping={isLooping}
                />
              </div>
            </div>
          )}
        </section>

        <section className="bg-white rounded-2xl p-6 shadow-xl border border-slate-100">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-6">
            <div className="flex items-center gap-3">
              <h2 className="text-sm font-bold text-slate-400 uppercase tracking-widest flex items-center gap-2">
                <Activity size={16} /> Émotions
              </h2>
              <button
                onClick={() => setIsLooping(l => !l)}
                className={`flex items-center gap-1.5 text-xs font-bold px-3 py-1.5 rounded-full transition-all ${isLooping ? 'bg-blue-600 text-white hover:bg-blue-700 shadow-sm' : 'bg-slate-100 text-slate-500 hover:bg-slate-200'}`}
                title="Rejouer en boucle l'animation sélectionnée"
              >
                <RotateCcw size={14} className={isLooping ? 'animate-spin' : ''} style={isLooping ? { animationDuration: '2s' } : undefined} />
                Loop
              </button>
            </div>
            <div className="flex flex-wrap items-end gap-4">
              <div className="flex flex-col gap-1">
                <span className="text-[10px] uppercase tracking-widest text-slate-400 font-bold ml-1">Personnage</span>
                <div className="flex items-center gap-2 bg-slate-50 p-1.5 rounded-lg border border-slate-200">
                  <User size={16} className="text-slate-400 ml-2" />
                  <select value={characterType} onChange={(e) => handleCharacterChange(e.target.value as CharacterType)} className="bg-transparent text-sm font-semibold text-slate-700 focus:outline-none cursor-pointer">
                    <option value="normal">Standard</option>
                    <option value="batman">Batman</option>
                    <option value="invincible">Invincible</option>
                    <option value="injured">Blessé</option>
                    <option value="sleeper">Dormeur</option>
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
              <button onClick={playDemo} disabled={isPlayingDemo || characterType === 'sleeper'} className={`flex items-center gap-2 text-sm font-semibold px-3 py-1.5 rounded-full transition-all ${isPlayingDemo || characterType === 'sleeper' ? 'bg-slate-100 text-slate-400 cursor-not-allowed' : 'bg-blue-50 text-blue-600 hover:bg-blue-100'}`}>
                {isPlayingDemo ? <Loader2 size={14} className="animate-spin" /> : <PlayCircle size={14} />}
                {isPlayingDemo ? 'Démo...' : 'Tout jouer'}
              </button>
            </div>
          </div>
          
          <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-8 gap-3">
            {[
              { id: Emotion.IDLE, label: 'Repos', icon: Activity, color: 'bg-slate-100 text-slate-600 hover:bg-slate-200' },
              { id: Emotion.JOY, label: 'Joie', icon: Smile, color: 'bg-green-100 text-green-600 hover:bg-green-200' },
              { id: Emotion.LAUGH, label: 'Rire', icon: Smile, color: 'bg-yellow-100 text-yellow-600 hover:bg-yellow-200' },
              { id: Emotion.SADNESS, label: 'Tristesse', icon: Meh, color: 'bg-indigo-100 text-indigo-600 hover:bg-indigo-200' },
              { id: Emotion.CRY, label: 'Pleure', icon: Frown, color: 'bg-blue-100 text-blue-600 hover:bg-blue-200' },
              { id: Emotion.PAIN, label: 'Douleur', icon: Zap, color: 'bg-red-100 text-red-600 hover:bg-red-200' },
              { id: Emotion.TERROR, label: 'Terreur', icon: AlertTriangle, color: 'bg-orange-100 text-orange-600 hover:bg-orange-200' },
              { id: Emotion.PUZZLED, label: 'Perplexe', icon: HelpCircle, color: 'bg-teal-100 text-teal-600 hover:bg-teal-200' },
              { id: Emotion.IMPATIENT, label: 'Moi !', icon: User, color: 'bg-pink-100 text-pink-600 hover:bg-pink-200' },
            ].map((btn) => {
              const blocked = characterType === 'sleeper' && btn.id !== Emotion.IDLE;
              return (
                <button
                  key={btn.id}
                  onClick={() => handleEmotion(btn.id)}
                  disabled={blocked}
                  className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === btn.id ? 'ring-2 ring-offset-2 ring-blue-500 shadow-md ' + btn.color : 'opacity-70 hover:opacity-100 bg-slate-50'} ${blocked ? '!opacity-30 !cursor-not-allowed hover:!scale-100' : ''}`}
                >
                  <btn.icon size={20} />
                  <span className="text-xs font-bold">{btn.label}</span>
                </button>
              );
            })}
          </div>
          <hr className="my-6 border-slate-100" />
          <div className="flex flex-col gap-6">
            <div className="flex gap-4 items-center">
              <h2 className="text-sm font-bold text-slate-400 uppercase tracking-widest flex items-center gap-2">
                <ArrowRight size={16} /> Sauts
              </h2>
              <div className={`flex flex-wrap gap-3 ${characterType === 'sleeper' ? 'opacity-30 pointer-events-none' : ''}`}>
                <button
                    onClick={() => handleEmotion(Emotion.JUMP_UP)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.JUMP_UP ? 'ring-2 ring-offset-2 ring-sky-500 shadow-md bg-sky-100 text-sky-600' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowUp size={20} />
                    <span className="text-xs font-bold">Saut Haut</span>
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.JUMP_DOWN)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.JUMP_DOWN ? 'ring-2 ring-offset-2 ring-amber-500 shadow-md bg-amber-100 text-amber-600' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowDown size={20} />
                    <span className="text-xs font-bold">Saut Bas</span>
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.JUMP_LEFT)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.JUMP_LEFT ? 'ring-2 ring-offset-2 ring-purple-500 shadow-md bg-purple-100 text-purple-600' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowLeft size={20} />
                    <span className="text-xs font-bold">Saut Gauche</span>
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.JUMP_RIGHT)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.JUMP_RIGHT ? 'ring-2 ring-offset-2 ring-teal-500 shadow-md bg-teal-100 text-teal-600' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowRight size={20} />
                    <span className="text-xs font-bold">Saut Droite</span>
                </button>
              </div>
            </div>

            <div className="flex gap-4 items-center">
              <h2 className="text-sm font-bold text-slate-400 uppercase tracking-widest flex items-center gap-2">
                <MoveHorizontal size={16} /> Glissades
              </h2>
              <div className={`flex flex-wrap gap-3 ${characterType === 'sleeper' ? 'opacity-30 pointer-events-none' : ''}`}>
                <button
                    onClick={() => handleEmotion(Emotion.SLIDE_UP)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.SLIDE_UP ? 'ring-2 ring-offset-2 ring-slate-400 shadow-md bg-slate-200 text-slate-800' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowUp size={20} />
                    <span className="text-xs font-bold">Glisser Haut</span>
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.SLIDE_DOWN)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.SLIDE_DOWN ? 'ring-2 ring-offset-2 ring-slate-400 shadow-md bg-slate-200 text-slate-800' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowDown size={20} />
                    <span className="text-xs font-bold">Glisser Bas</span>
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.SLIDE_LEFT)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.SLIDE_LEFT ? 'ring-2 ring-offset-2 ring-slate-400 shadow-md bg-slate-200 text-slate-800' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowLeft size={20} />
                    <span className="text-xs font-bold">Glisser Gauche</span>
                </button>
                <button
                    onClick={() => handleEmotion(Emotion.SLIDE_RIGHT)}
                    className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 w-32 transition-all transform hover:scale-105 active:scale-95 ${currentEmotion === Emotion.SLIDE_RIGHT ? 'ring-2 ring-offset-2 ring-slate-400 shadow-md bg-slate-200 text-slate-800' : 'opacity-70 hover:opacity-100 bg-slate-50 text-slate-600'}`}
                >
                    <ArrowRight size={20} />
                    <span className="text-xs font-bold">Glisser Droite</span>
                </button>
              </div>
            </div>
          </div>
        </section>
        </>
        )}

        {activeTab === 'dice' && (
          <>
            <section className={`flex-1 flex items-center justify-center min-h-[400px] rounded-3xl transition-all duration-500 relative overflow-hidden ${MAIN_BG_OPTIONS[mainBg]}${mainBg === 'vert' ? ' border-8 border-white/10 shadow-inner' : ''}`}>
              {mainBg === 'vert' && (
                <div className="absolute inset-0 opacity-10 pointer-events-none" style={{ backgroundImage: 'radial-gradient(circle at 2px 2px, white 1px, transparent 0)', backgroundSize: '40px 40px' }} />
              )}
              <div className="relative group">
                <div className={`absolute top-3/4 left-1/2 -translate-x-1/2 w-48 h-12 rounded-[100%] blur-2xl -z-10 ${mainBg === 'vert' ? 'bg-black/30' : 'bg-black/10'}`}></div>
                <img
                  key={diceRollKey}
                  src={getDiceSrc(diceDisplayValue, diceColor)}
                  alt={`Dé ${diceDisplayValue} ${diceColor}`}
                  className={`w-32 h-32 object-contain drop-shadow-lg select-none ${diceState === 'rolling' ? 'animate-dice-roll' : ''}`}
                />
              </div>
            </section>

            <section className="bg-white rounded-2xl p-6 shadow-xl border border-slate-100">
              <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-6">
                <h2 className="text-sm font-bold text-slate-400 uppercase tracking-widest flex items-center gap-2">
                  <Activity size={16} /> Animations
                </h2>
                <div className="flex flex-wrap items-center gap-4">
                  <div className="flex items-center gap-2 bg-slate-50 p-1.5 rounded-lg border border-slate-200">
                    <span className="text-xs font-bold text-slate-400 ml-2 uppercase tracking-wider">Valeur dé</span>
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
                    </select>
                  </div>
                </div>
              </div>
              <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-8 gap-3">
                <button
                  onClick={() => setDiceState('idle')}
                  className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 transition-all transform hover:scale-105 active:scale-95 ${diceState === 'idle' ? 'ring-2 ring-offset-2 ring-blue-500 shadow-md bg-slate-100 text-slate-600' : 'opacity-70 hover:opacity-100 bg-slate-50'}`}
                >
                  <Activity size={20} />
                  <span className="text-xs font-bold">Repos</span>
                </button>
                <button
                  onClick={rollDice}
                  disabled={diceState === 'rolling'}
                  className={`flex flex-col items-center justify-center p-3 rounded-xl gap-2 transition-all transform hover:scale-105 active:scale-95 ${diceState === 'rolling' ? 'ring-2 ring-offset-2 ring-orange-500 shadow-md bg-orange-100 text-orange-600' : 'opacity-70 hover:opacity-100 bg-slate-50'}`}
                >
                  <RotateCcw size={20} />
                  <span className="text-xs font-bold">Roll</span>
                </button>
              </div>
            </section>
          </>
        )}
      </main>
    </div>
  );
}
