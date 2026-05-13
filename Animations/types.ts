export enum Emotion {
  IDLE = 'IDLE',
  JOY = 'JOY',
  LAUGH = 'LAUGH',
  SADNESS = 'SADNESS',
  CRY = 'CRY',
  PAIN = 'PAIN',
  TERROR = 'TERROR',
  PUZZLED = 'PUZZLED',
  IMPATIENT = 'IMPATIENT',
  JUMP_RIGHT = 'JUMP_RIGHT',
  JUMP_LEFT = 'JUMP_LEFT',
  JUMP_UP = 'JUMP_UP',
  JUMP_DOWN = 'JUMP_DOWN',
  SLIDE_UP = 'SLIDE_UP',
  SLIDE_DOWN = 'SLIDE_DOWN',
  SLIDE_LEFT = 'SLIDE_LEFT',
  SLIDE_RIGHT = 'SLIDE_RIGHT'
}

export type CharacterType = 'normal' | 'batman' | 'invincible' | 'injured' | 'sleeper';

export interface AnimationState {
  emotion: Emotion;
  isAnimating: boolean;
}