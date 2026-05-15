import React from 'react';
import { TokenCharacter } from './TokenCharacter';
import { Emotion } from '../types';
import { Crown, Zap, Shield, Sparkles } from 'lucide-react';

export const LogoConcepts: React.FC = () => {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-8 p-4">
      {/* Concept 1: Crystal King */}
      <div className="bg-white p-6 rounded-3xl shadow-xl border border-slate-100 flex flex-col items-center gap-4 group hover:border-blue-300 transition-all">
        <div className="relative w-32 h-32 flex items-center justify-center">
          <div className="absolute -top-4 z-30 text-yellow-500 rotate-12 group-hover:rotate-0 transition-transform duration-500">
            <Crown size={48} fill="currentColor" strokeWidth={1} />
          </div>
          <div className="scale-75">
            <TokenCharacter emotion={Emotion.IDLE} characterType="invincible" color="blue" />
          </div>
        </div>
        <div className="text-center">
          <h3 className="font-bold text-slate-800">The Crystal King</h3>
          <p className="text-xs text-slate-500">Protection & Prestige</p>
        </div>
      </div>

      {/* Concept 2: Emotive Duel */}
      <div className="bg-white p-6 rounded-3xl shadow-xl border border-slate-100 flex flex-col items-center gap-4 group hover:border-red-300 transition-all">
        <div className="relative w-48 h-32 flex items-center justify-center gap-2">
          <div className="scale-50 -rotate-12 translate-x-4">
            <TokenCharacter emotion={Emotion.LAUGH} color="yellow" />
          </div>
          <div className="scale-50 rotate-12 -translate-x-4">
            <TokenCharacter emotion={Emotion.PAIN} color="red" />
          </div>
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
            <Zap size={32} className="text-orange-500 fill-orange-500 animate-pulse" />
          </div>
        </div>
        <div className="text-center">
          <h3 className="font-bold text-slate-800">LudoPoly Duel</h3>
          <p className="text-xs text-slate-500">Action & Interaction</p>
        </div>
      </div>

      {/* Concept 3: Modern Poly */}
      <div className="bg-slate-900 p-6 rounded-3xl shadow-xl border border-slate-700 flex flex-col items-center gap-4 group hover:border-green-400 transition-all">
        <div className="relative w-32 h-32 flex items-center justify-center">
          <div className="absolute inset-0 bg-gradient-to-tr from-green-500/20 to-blue-500/20 rounded-full blur-xl group-hover:blur-2xl transition-all" />
          <div className="scale-75">
             <TokenCharacter emotion={Emotion.JOY} color="green" />
          </div>
          <div className="absolute bottom-0 right-0 text-white flex gap-1">
             <Shield size={20} className="text-blue-400" />
             <Sparkles size={20} className="text-yellow-400" />
          </div>
        </div>
        <div className="text-center">
          <h3 className="font-bold text-white">Poly Shield</h3>
          <p className="text-xs text-slate-400">Innovation & Style</p>
        </div>
      </div>

      {/* Concept 4: Minimalist Token */}
      <div className="bg-blue-600 p-6 rounded-3xl shadow-xl flex flex-col items-center gap-4 group hover:bg-blue-700 transition-all">
        <div className="relative w-32 h-32 flex items-center justify-center">
          <div className="w-24 h-24 bg-white rounded-full flex items-center justify-center shadow-lg group-hover:scale-110 transition-transform">
             <div className="scale-50 translate-y-2">
                <TokenCharacter emotion={Emotion.IDLE} color="blue" characterType="standard" />
             </div>
          </div>
        </div>
        <div className="text-center">
          <h3 className="font-bold text-white">Iconic Token</h3>
          <p className="text-xs text-blue-200 font-medium">Clean & Professional</p>
        </div>
      </div>
    </div>
  );
};
