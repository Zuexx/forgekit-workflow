# i18n for forgekit-tanstack-start Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port forgekit's full 3-locale i18n setup (en/zh-TW/ko-KR) into `forgekit-tanstack-start`, using `react-i18next` in place of forgekit's Next.js-coupled `next-intl`, with locale resolution kept fully separate from the already-shipped ABAC guard.

**Architecture:** A pure locale-resolution function (`buildLocale`) mirrors sub-project 2's `buildContext`/`build-context.ts` pattern, wrapped by a `createServerFn`-based `resolveLocale` for the server-only cookie/header reads. `__root.tsx`'s `beforeLoad` runs locale resolution and the existing ABAC check as two independent steps that only rejoin when building a policy redirect's URL. A generic `RadialMenu` primitive (ported from forgekit's real component, not a stand-in) backs a new `LocaleSwitcher`, mounted on the sign-in/sign-up cards.

**Tech Stack:** `react-i18next`/`i18next` (message catalogs, hooks, typed keys via module augmentation), `motion` (spring animation), `lucide-react` (icons), StyleX (existing styling system) — no new dependency outside these four.

**Spec:** `docs/superpowers/specs/2026-09-21-tanstack-start-i18n-design.md`

## Global Constraints

- Library: `react-i18next`/`i18next`, never `next-intl` — next-intl's routing layer assumes Next.js's middleware model, which TanStack Start has no equivalent for.
- Locales: `en` (default, no URL prefix), `zh-TW`, `ko-KR` — full replication of forgekit's current set, not a reduction (that decision belongs to sub-project 7).
- `evaluatePolicy`/`resolveContext`/`AbacContext` (`app/src/shared/api/abac/`) get **zero** interface changes. They keep receiving an already-locale-stripped path. Locale resolution never enters their types.
- Dependency versions pinned to match forgekit's `app/package.json` exactly: `motion@^13.2.0`, `lucide-react@^1.45.0`. `i18next@^26.4.2`, `react-i18next@^17.0.14` have no forgekit equivalent to match (forgekit uses next-intl) — pin to the latest mutually-compatible release pair as of this plan's writing.
- FSD placement: everything lives under one `shared/i18n/` segment (catalogs, config, resolution logic, the one piece of coupled UI) plus a generic `shared/ui/radial-menu.tsx` — confirmed directly against the installed `@feature-sliced/steiger-plugin@0.7.0`'s bad-names list that `i18n` is not a flagged segment name, and that `shared`/`app` layers are exempt from the `insignificant-slice` rule (unlike `features`/`entities`/`widgets`). Every task in this plan can therefore be reviewed and merged individually with fully green CI — no branch-stacking workaround is needed this time (unlike sub-project 2, which needed one for exactly this class of constraint).
- Any `beforeLoad` step that calls a `createServerFn`-wrapped RPC must fail open (let the request through on error), matching the established pattern from sub-project 2's final-review fix to the ABAC gate — this sub-project's own new locale-resolution RPC follows the identical discipline from day one, not as a fix-later item.
- No automated test exercises `__root.tsx`'s actual `beforeLoad` wiring at the router level — verified manually against a real dev server instead, matching the exact same accepted gap already recorded for sub-projects 1 and 2.

---

### Task 1: Locale config, message catalogs, and the i18next instance factory

**Files:**
- Modify: `app/tsconfig.json` (add `resolveJsonModule: true`)
- Modify: `app/package.json` (add `i18next`, `react-i18next`, `motion`, `lucide-react`)
- Create: `app/src/shared/i18n/config.ts`
- Create: `app/src/shared/i18n/locales/en/{auth,common,form,toast,validation}.json`
- Create: `app/src/shared/i18n/locales/zh-TW/{auth,common,form,toast,validation}.json`
- Create: `app/src/shared/i18n/locales/ko-KR/{auth,common,form,toast,validation}.json`
- Create: `app/src/shared/i18n/i18n.ts`
- Create: `app/src/shared/i18n/react-i18next.d.ts`
- Test: `app/src/shared/i18n/i18n.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks (first task).
- Produces: `SUPPORTED_LOCALES: readonly Locale[]`, `DEFAULT_LOCALE: Locale`, `LOCALE_COOKIE: string`, `NAMESPACES: readonly Namespace[]` (all from `config.ts`); `createI18nInstance(locale: Locale): i18n` (from `i18n.ts`) — later tasks (3, 7) call this to build a request-scoped i18next instance.

- [ ] **Step 1: Add `resolveJsonModule` to tsconfig**

Modify `app/tsconfig.json`'s `compilerOptions` — add one line so `tsc --noEmit` (this repo's `pnpm check`) accepts the JSON imports this task adds:

```json
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "allowImportingTsExtensions": true,
```

- [ ] **Step 2: Add the new dependencies**

In `app/package.json`'s `"dependencies"` block, add (keep the existing alphabetical order):

```json
    "i18next": "^26.4.2",
    "lucide-react": "^1.45.0",
    "motion": "^13.2.0",
```

and:

```json
    "react-i18next": "^17.0.14",
```

in its alphabetical position. Run `cd app && pnpm install` and confirm `app/pnpm-lock.yaml` picks up the four new entries.

- [ ] **Step 3: Create the locale config**

Create `app/src/shared/i18n/config.ts`:

```typescript
export const SUPPORTED_LOCALES = ['en', 'zh-TW', 'ko-KR'] as const
export type Locale = (typeof SUPPORTED_LOCALES)[number]

export const DEFAULT_LOCALE: Locale = 'en'

export const NAMESPACES = ['auth', 'common', 'form', 'toast', 'validation'] as const
export type Namespace = (typeof NAMESPACES)[number]

export const LOCALE_COOKIE = 'forgekit-tanstack-start.locale'

export function isLocale(value: string): value is Locale {
  return (SUPPORTED_LOCALES as readonly string[]).includes(value)
}
```

- [ ] **Step 4: Create the message catalogs**

Create `app/src/shared/i18n/locales/en/auth.json`:

```json
{
  "signIn": {
    "subtitle": "Your Application",
    "loginWithSSO": "Login with SSO",
    "orContinueWith": "Or continue with",
    "forgotPassword": "Forgot your password?",
    "loginButton": "Login",
    "signupPrompt": "Don't have an account?",
    "signupCTA": "Sign up"
  },
  "signUp": {
    "subtitle": "Your Application",
    "signUpDesc": "Enter your email below to create your account",
    "passwordHint": "Must be at least 8 characters long.",
    "createAccountButton": "Create Account",
    "signinPrompt": "Already have an account?",
    "signinCTA": "Sign In"
  }
}
```

Create `app/src/shared/i18n/locales/en/common.json`:

```json
{
  "tos": {
    "prefix": "By clicking continue, you agree to our",
    "and": "and",
    "terms": "Terms of Service",
    "privacy": "Privacy Policy"
  }
}
```

Create `app/src/shared/i18n/locales/en/form.json`:

```json
{
  "fullName": {
    "label": "Full Name",
    "placeholder": "Enter you name"
  },
  "email": {
    "label": "Email",
    "placeholder": "name@example.com"
  },
  "password": {
    "label": "Password",
    "placeholder": "Enter your password (case-sensitive)"
  },
  "signUp": {
    "password": {
      "label": "Password",
      "placeholder": "Password"
    },
    "confirmPassword": {
      "label": "Confirm Password",
      "placeholder": "Confirm Password"
    }
  }
}
```

Create `app/src/shared/i18n/locales/en/toast.json`:

```json
{
  "success": {
    "signIn": "Signed in successfully",
    "signUp": "Account created successfully",
    "signOut": "Signed out successfully",
    "default": "Operation successful",
    "fetchCurrent": "Fetched current user"
  },
  "error": {
    "signIn": "Sign in failed. Please check your credentials",
    "signUp": "Sign up failed. Please check your details",
    "signOut": "Sign out failed",
    "default": "Operation failed. Please try again",
    "network": "Network connection failed",
    "fetchCurrent": "Failed to fetch current user"
  },
  "loading": {
    "signIn": "Signing in...",
    "signUp": "Creating account...",
    "default": "Processing..."
  }
}
```

Create `app/src/shared/i18n/locales/en/validation.json`:

```json
{
  "authenticate": {
    "name": {
      "required": "Name is required",
      "invalid": "Please enter your name"
    },
    "email": {
      "required": "Email is required",
      "invalid": "Please enter a valid email address"
    },
    "password": {
      "required": "Password is required",
      "min": "Password must be at least {{min}} characters"
    },
    "confirmPassword": {
      "required": "Confirm Password is required",
      "confirm": "Password not matched"
    }
  }
}
```

(Note the `{{min}}` double-brace form — this is `i18next`'s interpolation syntax, not `next-intl`'s single-brace `{min}`. Every other namespace file is copied byte-for-byte from forgekit; this is the one intentional syntax change, needed by the library switch.)

Create `app/src/shared/i18n/locales/zh-TW/auth.json`:

```json
{
  "signIn": {
    "subtitle": "您的應用程式",
    "loginWithSSO": "使用 SSO 帳號登入",
    "orContinueWith": "或使用以下方式登入",
    "forgotPassword": "忘記密碼？",
    "loginButton": "登入",
    "signupPrompt": "尚未建立帳號？",
    "signupCTA": "申請帳號"
  },
  "signUp": {
    "subtitle": "您的應用程式",
    "signUpDesc": "請在下方輸入電子郵件以建立帳號",
    "passwordHint": "密碼長度至少需為 8 個字元。",
    "createAccountButton": "建立帳號",
    "signinPrompt": "已經有帳號了嗎？",
    "signinCTA": "登入"
  }
}
```

Create `app/src/shared/i18n/locales/zh-TW/common.json`:

```json
{
  "tos": {
    "prefix": "點擊繼續即表示您同意本系統的",
    "and": "以及",
    "terms": "服務條款",
    "privacy": "隱私權政策"
  }
}
```

Create `app/src/shared/i18n/locales/zh-TW/form.json`:

```json
{
  "fullName": {
    "label": "姓名",
    "placeholder": "請輸入姓名"
  },
  "email": {
    "label": "電子郵件地址",
    "placeholder": "name@example.com"
  },
  "password": {
    "label": "密碼",
    "placeholder": "請輸入密碼（區分大小寫）"
  },
  "signUp": {
    "password": {
      "label": "密碼",
      "placeholder": "密碼"
    },
    "confirmPassword": {
      "label": "確認密碼",
      "placeholder": "確認密碼"
    }
  }
}
```

Create `app/src/shared/i18n/locales/zh-TW/toast.json`:

```json
{
  "success": {
    "signIn": "登入成功",
    "signUp": "註冊成功",
    "signOut": "登出成功",
    "default": "操作成功",
    "fetchCurrent": "取得當前使用者成功"
  },
  "error": {
    "signIn": "登入失敗，請檢查您的帳號密碼",
    "signUp": "註冊失敗，請檢查您輸入的資料",
    "signOut": "登出失敗",
    "default": "操作失敗，請稍後再試",
    "network": "網路連線失敗",
    "fetchCurrent": "取得當前使用者失敗"
  },
  "loading": {
    "signIn": "登入中...",
    "signUp": "註冊中...",
    "default": "處理中..."
  }
}
```

Create `app/src/shared/i18n/locales/zh-TW/validation.json`:

```json
{
  "authenticate": {
    "name": {
      "required": "請輸入姓名",
      "invalid": "請輸入有效的姓名"
    },
    "email": {
      "required": "請輸入電子郵件地址",
      "invalid": "請輸入有效的電子郵件地址"
    },
    "password": {
      "required": "請輸入密碼",
      "min": "密碼長度至少需為 {{min}} 個字元"
    },
    "confirmPassword": {
      "required": "請輸入確認密碼",
      "confirm": "密碼不一致"
    }
  }
}
```

Create `app/src/shared/i18n/locales/ko-KR/auth.json`:

```json
{
  "signIn": {
    "subtitle": "귀하의 애플리케이션",
    "loginWithSSO": "SSO 계정으로 로그인",
    "orContinueWith": "또는 다음 방법으로 계속",
    "forgotPassword": "비밀번호를 잊으셨습니까?",
    "loginButton": "로그인",
    "signupPrompt": "계정이 없으신가요?",
    "signupCTA": "계정 신청"
  },
  "signUp": {
    "subtitle": "귀하의 애플리케이션",
    "signUpDesc": "아래에 이메일을 입력하여 계정을 생성하세요",
    "passwordHint": "비밀번호는 최소 8자 이상이어야 합니다.",
    "createAccountButton": "계정 생성",
    "signinPrompt": "이미 계정이 있으신가요?",
    "signinCTA": "로그인"
  }
}
```

Create `app/src/shared/i18n/locales/ko-KR/common.json`:

```json
{
  "tos": {
    "prefix": "계속 진행하면 본 시스템의",
    "and": "및",
    "terms": "서비스 이용약관",
    "privacy": "개인정보 처리방침"
  }
}
```

Create `app/src/shared/i18n/locales/ko-KR/form.json`:

```json
{
  "fullName": {
    "label": "이름",
    "placeholder": "이름을 입력하세요"
  },
  "email": {
    "label": "이메일",
    "placeholder": "name@example.com"
  },
  "password": {
    "label": "비밀번호",
    "placeholder": "비밀번호를 입력하세요 (대소문자 구분)"
  },
  "signUp": {
    "password": {
      "label": "비밀번호",
      "placeholder": "비밀번호"
    },
    "confirmPassword": {
      "label": "비밀번호 확인",
      "placeholder": "비밀번호 확인"
    }
  }
}
```

Create `app/src/shared/i18n/locales/ko-KR/toast.json`:

```json
{
  "success": {
    "signIn": "로그인 성공",
    "signUp": "회원가입 성공",
    "signOut": "로그아웃 성공",
    "default": "작업 성공",
    "fetchCurrent": "현재 사용자 가져오기 성공"
  },
  "error": {
    "signIn": "로그인 실패. 계정 정보를 확인해주세요",
    "signUp": "회원가입 실패. 입력한 정보를 확인해주세요",
    "signOut": "로그아웃 실패",
    "default": "작업 실패. 다시 시도해주세요",
    "network": "네트워크 연결 실패",
    "fetchCurrent": "현재 사용자 가져오기 실패"
  },
  "loading": {
    "signIn": "로그인 중...",
    "signUp": "회원가입 중...",
    "default": "처리 중..."
  }
}
```

Create `app/src/shared/i18n/locales/ko-KR/validation.json`:

```json
{
  "authenticate": {
    "name": {
      "required": "이름은 필수 입력 항목입니다",
      "invalid": "이름을 입력해 주세요"
    },
    "email": {
      "required": "이메일 주소를 입력해 주세요",
      "invalid": "유효한 이메일 주소를 입력해 주세요"
    },
    "password": {
      "required": "비밀번호를 입력해 주세요",
      "min": "비밀번호는 최소 {{min}}자 이상이어야 합니다"
    },
    "confirmPassword": {
      "required": "비밀번호 확인을 입력해 주세요",
      "confirm": "비밀번호가 일치하지 않습니다"
    }
  }
}
```

- [ ] **Step 5: Create the i18next instance factory**

Create `app/src/shared/i18n/i18n.ts`:

```typescript
import i18next from 'i18next'
import { initReactI18next } from 'react-i18next'

import type { Locale } from './config'
import { DEFAULT_LOCALE, NAMESPACES } from './config'

import enAuth from './locales/en/auth.json'
import enCommon from './locales/en/common.json'
import enForm from './locales/en/form.json'
import enToast from './locales/en/toast.json'
import enValidation from './locales/en/validation.json'
import zhTWAuth from './locales/zh-TW/auth.json'
import zhTWCommon from './locales/zh-TW/common.json'
import zhTWForm from './locales/zh-TW/form.json'
import zhTWToast from './locales/zh-TW/toast.json'
import zhTWValidation from './locales/zh-TW/validation.json'
import koKRAuth from './locales/ko-KR/auth.json'
import koKRCommon from './locales/ko-KR/common.json'
import koKRForm from './locales/ko-KR/form.json'
import koKRToast from './locales/ko-KR/toast.json'
import koKRValidation from './locales/ko-KR/validation.json'

const resources = {
  en: {
    auth: enAuth,
    common: enCommon,
    form: enForm,
    toast: enToast,
    validation: enValidation,
  },
  'zh-TW': {
    auth: zhTWAuth,
    common: zhTWCommon,
    form: zhTWForm,
    toast: zhTWToast,
    validation: zhTWValidation,
  },
  'ko-KR': {
    auth: koKRAuth,
    common: koKRCommon,
    form: koKRForm,
    toast: koKRToast,
    validation: koKRValidation,
  },
}

/**
 * A fresh instance per call, not a shared module-level singleton — request isolation
 * matters here the same way it already does for this app's Zustand store (sub-project 1's
 * per-request StateProvider decision): a singleton would leak one visitor's locale into
 * another's concurrent SSR render.
 */
export function createI18nInstance(locale: Locale) {
  const instance = i18next.createInstance()
  void instance.use(initReactI18next).init({
    lng: locale,
    fallbackLng: DEFAULT_LOCALE,
    resources,
    ns: NAMESPACES,
    defaultNS: 'common',
    interpolation: { escapeValue: false },
  })
  return instance
}
```

- [ ] **Step 6: Create the typed-keys module augmentation**

Create `app/src/shared/i18n/react-i18next.d.ts`:

```typescript
import 'react-i18next'

import type auth from './locales/en/auth.json'
import type common from './locales/en/common.json'
import type form from './locales/en/form.json'
import type toast from './locales/en/toast.json'
import type validation from './locales/en/validation.json'

declare module 'react-i18next' {
  interface CustomTypeOptions {
    defaultNS: 'common'
    resources: {
      auth: typeof auth
      common: typeof common
      form: typeof form
      toast: typeof toast
      validation: typeof validation
    }
  }
}
```

- [ ] **Step 7: Write the instance-factory test**

Create `app/src/shared/i18n/i18n.test.ts`:

```typescript
import { describe, expect, it } from 'vitest'

import { createI18nInstance } from './i18n'

describe('createI18nInstance', () => {
  it('resolves a key from the requested locale', () => {
    const i18n = createI18nInstance('zh-TW')
    expect(i18n.t('common:tos.terms')).toBe('服務條款')
  })

  it('resolves the same key from a different locale', () => {
    const i18n = createI18nInstance('en')
    expect(i18n.t('common:tos.terms')).toBe('Terms of Service')
  })

  it('interpolates a validation message', () => {
    const i18n = createI18nInstance('en')
    expect(i18n.t('validation:authenticate.password.min', { min: 8 })).toBe(
      'Password must be at least 8 characters',
    )
  })

  it('creates independent instances per call', () => {
    const first = createI18nInstance('en')
    const second = createI18nInstance('zh-TW')
    expect(first.language).toBe('en')
    expect(second.language).toBe('zh-TW')
  })
})
```

- [ ] **Step 8: Run the test and the full check suite**

```bash
cd app
pnpm test i18n.test.ts
pnpm check
pnpm lint
pnpm lint:fsd
```

Expected: all pass. `pnpm lint:fsd` still reports "No problems found!" (`i18n` is not on steiger's bad-names list, confirmed directly against the installed plugin before this plan was written).

- [ ] **Step 9: Commit**

```bash
git add app/tsconfig.json app/package.json app/pnpm-lock.yaml app/src/shared/i18n
git commit -m "feat: add locale config, message catalogs, and i18next instance factory"
```

---

### Task 2: Locale resolution (pure core + server wrapper)

**Files:**
- Create: `app/src/shared/i18n/build-locale.ts`
- Create: `app/src/shared/i18n/build-locale.test.ts`
- Create: `app/src/shared/i18n/resolve-locale.ts`

**Interfaces:**
- Consumes: `SUPPORTED_LOCALES`, `DEFAULT_LOCALE`, `LOCALE_COOKIE`, `isLocale` from `./config` (Task 1).
- Produces: `buildLocale(path: string, cookieLocale: string | undefined, acceptLanguage: string | undefined): { locale: Locale; path: string }`, `withLocalePrefix(path: string, locale: Locale): string` (both from `build-locale.ts`); `resolveLocale(path: string): Promise<{ locale: Locale; path: string }>` (from `resolve-locale.ts`) — Task 3 calls both `resolveLocale` and `withLocalePrefix`.

- [ ] **Step 1: Write the failing tests for `buildLocale`/`withLocalePrefix`**

Create `app/src/shared/i18n/build-locale.test.ts`:

```typescript
import { describe, expect, it } from 'vitest'

import { buildLocale, withLocalePrefix } from './build-locale'

describe('buildLocale', () => {
  it('takes the locale from a leading path segment', () => {
    const result = buildLocale('/zh-TW/dashboard', undefined, undefined)
    expect(result).toEqual({ locale: 'zh-TW', path: '/dashboard' })
  })

  it('normalizes a bare locale-only path to root', () => {
    const result = buildLocale('/en', undefined, undefined)
    expect(result).toEqual({ locale: 'en', path: '/' })
  })

  it('does not treat a look-alike segment as a locale', () => {
    const result = buildLocale('/english/page', undefined, undefined)
    expect(result.locale).toBe('en')
    expect(result.path).toBe('/english/page')
  })

  it('strips only the leading locale segment, never a later occurrence', () => {
    const result = buildLocale('/zh-TW/enroll', undefined, undefined)
    expect(result).toEqual({ locale: 'zh-TW', path: '/enroll' })
  })

  it('falls back to a valid cookie locale when the path has no prefix', () => {
    const result = buildLocale('/dashboard', 'ko-KR', undefined)
    expect(result).toEqual({ locale: 'ko-KR', path: '/dashboard' })
  })

  it('ignores an invalid cookie value and falls through to negotiation', () => {
    const result = buildLocale('/dashboard', 'fr', 'ko-KR,en;q=0.5')
    expect(result.locale).toBe('ko-KR')
  })

  it('negotiates a supported locale from Accept-Language when no path/cookie locale exists', () => {
    const result = buildLocale('/dashboard', undefined, 'zh-TW,en;q=0.8')
    expect(result).toEqual({ locale: 'zh-TW', path: '/dashboard' })
  })

  it('falls back to the default locale when nothing matches', () => {
    const result = buildLocale('/dashboard', undefined, 'fr-FR,de;q=0.5')
    expect(result).toEqual({ locale: 'en', path: '/dashboard' })
  })

  it('falls back to the default locale when there is no Accept-Language at all', () => {
    const result = buildLocale('/dashboard', undefined, undefined)
    expect(result).toEqual({ locale: 'en', path: '/dashboard' })
  })
})

describe('withLocalePrefix', () => {
  it('adds no prefix for the default locale', () => {
    expect(withLocalePrefix('/sign-in', 'en')).toBe('/sign-in')
  })

  it('prefixes a non-default locale', () => {
    expect(withLocalePrefix('/sign-in', 'zh-TW')).toBe('/zh-TW/sign-in')
  })

  it('prefixes the root path without a double slash', () => {
    expect(withLocalePrefix('/', 'ko-KR')).toBe('/ko-KR')
  })
})
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd app
pnpm test build-locale.test.ts
```

Expected: FAIL — `build-locale.ts` doesn't exist yet.

- [ ] **Step 3: Implement `buildLocale`/`withLocalePrefix`**

Create `app/src/shared/i18n/build-locale.ts`:

```typescript
import type { Locale } from './config'
import { DEFAULT_LOCALE, SUPPORTED_LOCALES, isLocale } from './config'

/**
 * The pure half of locale resolution — no server-only imports, so it's directly
 * unit-testable with plain values. resolve-locale.ts (a createServerFn wrapper — it can
 * only run inside TanStack Start's real request runtime) reads the actual cookie/header
 * values and passes them in here. Mirrors sub-project 2's build-context.ts/resolve-context.ts
 * split for the exact same reason.
 */
export function buildLocale(
  path: string,
  cookieLocale: string | undefined,
  acceptLanguage: string | undefined,
): { locale: Locale; path: string } {
  const segments = path.split('/')
  const leadingSegment = segments[1] ?? ''

  if (isLocale(leadingSegment)) {
    const rest = `/${segments.slice(2).join('/')}`
    return { locale: leadingSegment, path: rest === '/' ? '/' : rest.replace(/\/+$/, '') }
  }

  if (cookieLocale && isLocale(cookieLocale)) {
    return { locale: cookieLocale, path }
  }

  return { locale: negotiateLocale(acceptLanguage), path }
}

function negotiateLocale(acceptLanguage: string | undefined): Locale {
  if (!acceptLanguage) {
    return DEFAULT_LOCALE
  }

  const preferences = acceptLanguage
    .split(',')
    .map((part) => part.split(';')[0]?.trim().toLowerCase())
    .filter((part): part is string => Boolean(part))

  for (const preference of preferences) {
    const match = SUPPORTED_LOCALES.find(
      (locale) =>
        locale.toLowerCase() === preference ||
        preference.startsWith(`${locale.toLowerCase().split('-')[0]}-`) ||
        preference === locale.toLowerCase().split('-')[0],
    )
    if (match) {
      return match
    }
  }

  return DEFAULT_LOCALE
}

export function withLocalePrefix(path: string, locale: Locale): string {
  if (locale === DEFAULT_LOCALE) {
    return path
  }
  return path === '/' ? `/${locale}` : `/${locale}${path}`
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd app
pnpm test build-locale.test.ts
```

Expected: PASS, all 12 cases.

- [ ] **Step 5: Implement the server wrapper**

Create `app/src/shared/i18n/resolve-locale.ts`:

```typescript
import { createServerFn } from '@tanstack/react-start'
import { getCookie, getRequestHeader } from '@tanstack/react-start/server'

import type { Locale } from './config'
import { LOCALE_COOKIE } from './config'
import { buildLocale } from './build-locale'

/**
 * getCookie/getRequestHeader are server-only APIs, same import-protection constraint
 * documented in shared/api/abac/resolve-context.ts and shared/api/require-session.ts —
 * createServerFn is the bridge. No test of its own: it can only run inside TanStack
 * Start's real request runtime ("No Start context found in AsyncLocalStorage" outside
 * it), same accepted gap as those two files. buildLocale (above) carries the real,
 * directly-tested logic.
 */
const resolveLocaleFn = createServerFn({ method: 'GET' })
  .validator((data: { path: string }) => data)
  .handler(({ data }) => {
    const cookieLocale = getCookie(LOCALE_COOKIE)
    const acceptLanguage = getRequestHeader('accept-language')
    return buildLocale(data.path, cookieLocale, acceptLanguage)
  })

export function resolveLocale(path: string): Promise<{ locale: Locale; path: string }> {
  return resolveLocaleFn({ data: { path } })
}
```

- [ ] **Step 6: Run the full check suite**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm test
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add app/src/shared/i18n/build-locale.ts app/src/shared/i18n/build-locale.test.ts app/src/shared/i18n/resolve-locale.ts
git commit -m "feat: add locale resolution (pure build-locale + createServerFn wrapper)"
```

---

### Task 3: Wire locale into `__root.tsx` and mount the i18next provider

**Files:**
- Modify: `app/src/routes/__root.tsx`
- Modify: `app/src/app/root-document.tsx`

**Interfaces:**
- Consumes: `resolveLocale`, `withLocalePrefix` (Task 2); `createI18nInstance`, `DEFAULT_LOCALE`, `Locale` (Task 1); `evaluatePolicy`, `resolveContext` (sub-project 2, unchanged).
- Produces: `beforeLoad` returns `{ locale: Locale }` in route context — Task 5 (`LocaleSwitcher`) and any future route reads `Route.useRouteContext()`/`useRouteContext({ from: '__root__' })` to get it.

- [ ] **Step 1: Read the current `__root.tsx`**

It currently reads (confirmed against the repo before writing this task):

```tsx
import { createRootRoute, redirect } from '@tanstack/react-router'

import { evaluatePolicy, resolveContext } from '#/shared/api/abac'
import { ABAC_CONFIG } from '#/shared/lib/abac-config'
import { RootDocument } from '#/app/root-document'
import appCss from '../styles.css?url'

export const Route = createRootRoute({
  beforeLoad: async ({ location }) => {
    let decision
    try {
      decision = evaluatePolicy(
        await resolveContext(location.pathname, ABAC_CONFIG),
      )
    } catch {
      // Fail open: this gate is a cheap redirect convenience, not the real authorization
      // boundary — requireSession() on protected routes is, so letting a transient
      // resolveContext RPC failure through here (rather than breaking every route,
      // including public ones) doesn't create a security hole.
      return
    }
    if (decision.effect === 'redirect') {
      throw redirect({ to: decision.to })
    }
  },
  head: () => ({ /* unchanged */ }),
  shellComponent: RootDocument,
})
```

- [ ] **Step 2: Add the locale-resolution step**

Replace the `beforeLoad` body with a version that resolves locale first (fail-open to `DEFAULT_LOCALE` on error, the same discipline as the ABAC step right below it), strips the locale segment before handing the path to `resolveContext` (unchanged interface), and prefixes any policy redirect with the resolved locale:

```tsx
import { createRootRoute, redirect } from '@tanstack/react-router'

import { evaluatePolicy, resolveContext } from '#/shared/api/abac'
import { ABAC_CONFIG } from '#/shared/lib/abac-config'
import { DEFAULT_LOCALE } from '#/shared/i18n/config'
import type { Locale } from '#/shared/i18n/config'
import { resolveLocale } from '#/shared/i18n/resolve-locale'
import { withLocalePrefix } from '#/shared/i18n/build-locale'
import { RootDocument } from '#/app/root-document'
import appCss from '../styles.css?url'

export const Route = createRootRoute({
  beforeLoad: async ({ location }) => {
    let locale: Locale = DEFAULT_LOCALE
    let path = location.pathname
    try {
      const localeResult = await resolveLocale(location.pathname)
      locale = localeResult.locale
      path = localeResult.path
    } catch {
      // Fail open to the default locale — same reasoning as the ABAC gate below: this
      // step is a convenience, not a security boundary, so a transient RPC failure
      // shouldn't break every route.
    }

    let decision
    try {
      decision = evaluatePolicy(await resolveContext(path, ABAC_CONFIG))
    } catch {
      return { locale }
    }
    if (decision.effect === 'redirect') {
      throw redirect({ to: withLocalePrefix(decision.to, locale) })
    }
    return { locale }
  },
  head: () => ({ /* unchanged */ }),
  shellComponent: RootDocument,
})
```

Keep the existing `head` function's body exactly as it is today — only `beforeLoad` changes.

- [ ] **Step 3: Mount the i18next provider in `root-document.tsx`**

The current file:

```tsx
import { HeadContent, Scripts } from '@tanstack/react-router'
import { Toaster } from 'react-hot-toast'

import { QueryProvider, useSyncAuthSession } from '#/shared/api'
import { StateProvider } from '#/shared/state'

function AuthSessionSync({ children }: { children: React.ReactNode }) {
  useSyncAuthSession()
  return <>{children}</>
}

export function RootDocument({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
        {import.meta.env.DEV && (
          <script type="module" src="/@id/virtual:stylex:runtime" />
        )}
      </head>
      <body>
        <StateProvider>
          <QueryProvider>
            <AuthSessionSync>{children}</AuthSessionSync>
          </QueryProvider>
        </StateProvider>
        <Toaster position="bottom-right" />

        <Scripts />
      </body>
    </html>
  )
}
```

Add an `I18nProvider` wrapper (same shape as the existing `AuthSessionSync`, reading the root route's context via `useRouteContext`) around the same subtree, and use the resolved locale for the `<html lang>` attribute too:

```tsx
import { HeadContent, Scripts, useRouteContext } from '@tanstack/react-router'
import { useMemo } from 'react'
import { I18nextProvider } from 'react-i18next'
import { Toaster } from 'react-hot-toast'

import { QueryProvider, useSyncAuthSession } from '#/shared/api'
import { StateProvider } from '#/shared/state'
import { createI18nInstance } from '#/shared/i18n/i18n'

function AuthSessionSync({ children }: { children: React.ReactNode }) {
  useSyncAuthSession()
  return <>{children}</>
}

function I18nProvider({ children }: { children: React.ReactNode }) {
  const { locale } = useRouteContext({ from: '__root__' })
  const i18n = useMemo(() => createI18nInstance(locale), [locale])
  return <I18nextProvider i18n={i18n}>{children}</I18nextProvider>
}

export function RootDocument({ children }: { children: React.ReactNode }) {
  const { locale } = useRouteContext({ from: '__root__' })

  return (
    <html lang={locale}>
      <head>
        <HeadContent />
        {import.meta.env.DEV && (
          <script type="module" src="/@id/virtual:stylex:runtime" />
        )}
      </head>
      <body>
        <StateProvider>
          <QueryProvider>
            <I18nProvider>
              <AuthSessionSync>{children}</AuthSessionSync>
            </I18nProvider>
          </QueryProvider>
        </StateProvider>
        <Toaster position="bottom-right" />

        <Scripts />
      </body>
    </html>
  )
}
```

- [ ] **Step 4: Run the full check suite**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm test
pnpm build
```

Expected: all pass/succeed. No test file covers `beforeLoad`'s wiring itself (see Step 5) or `RootDocument`'s route-context read directly — both are accepted gaps in this repo's established testing pattern for route-level wiring.

- [ ] **Step 5: Manually verify against a real dev server**

```bash
cd app
pnpm dev &
sleep 5

# Default locale, no prefix: plain 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/

# Non-default locale prefix on the public route: still 200, locale-stripped path resolves
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/zh-TW/

# Unauthenticated visit to a locale-prefixed protected-looking path — the ABAC gate
# only classifies '/sign-in'/'/sign-up' as auth routes and '/' as public; anything else
# falls to the implicit-deny branch. /dashboard is registered (sub-project 2) and
# unauthenticated, so this must 307 to the SAME locale's /sign-in — the redirect-prefix
# hazard this plan's design explicitly set out to avoid:
curl -s -i http://localhost:3000/zh-TW/dashboard | grep -i "^location\|^HTTP"

# Accept-Language negotiation on the unprefixed root:
curl -s -o /dev/null -w "%{http_code}\n" -H "Accept-Language: ko-KR,en;q=0.5" http://localhost:3000/

kill %1
```

Expected: first three all 200 (or the dashboard curl's `-i` shows a 307 with `location: /zh-TW/sign-in` — the locale prefix must survive the redirect chain). This confirms the plan's core design goal (no next-intl-style redirect-ordering hazard) empirically, on the real integrated code, not just in `build-locale.test.ts`'s isolated unit tests.

- [ ] **Step 6: Commit**

```bash
git add app/src/routes/__root.tsx app/src/app/root-document.tsx
git commit -m "feat: wire locale resolution into __root.tsx and mount the i18next provider"
```

---

### Task 4: `RadialMenu` — generic shared UI primitive

**Files:**
- Create: `app/src/shared/ui/radial-menu.tsx`
- Test: `app/src/shared/ui/radial-menu.test.tsx`

**Interfaces:**
- Consumes: `Button` (`#/shared/ui/button`), `colors`/`radius` (`#/shared/lib/tokens.stylex`) — all pre-existing.
- Produces: `RadialMenu`, `RadialMenuItem` (props type) — Task 5 (`LocaleSwitcher`) builds on this.

- [ ] **Step 1: Write the failing tests**

Create `app/src/shared/ui/radial-menu.test.tsx`:

```tsx
import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { RadialMenu } from './radial-menu'

afterEach(() => {
  cleanup()
})

describe('RadialMenu', () => {
  it('renders the toggle and one button per item, closed by default', () => {
    render(
      <RadialMenu
        items={[{ label: 'A' }, { label: 'B' }, { label: 'C' }]}
        toggleAriaLabel="Open menu"
      />,
    )
    expect(screen.getByRole('button', { name: 'Open menu' })).toBeInTheDocument()
    expect(screen.getAllByRole('button')).toHaveLength(4) // toggle + 3 items
  })

  it('opens on click and fires an item onClick, then closes', async () => {
    const onClick = vi.fn()
    render(
      <RadialMenu
        items={[{ label: 'A', onClick }, { label: 'B' }]}
        toggleAriaLabel="Open menu"
        trigger="click"
      />,
    )

    await userEvent.click(screen.getByRole('button', { name: 'Open menu' }))
    await userEvent.click(screen.getByRole('button', { name: 'A' }))

    expect(onClick).toHaveBeenCalledOnce()
  })

  it('opens on hover when trigger is "hover"', async () => {
    render(
      <RadialMenu
        items={[{ label: 'A' }]}
        toggleAriaLabel="Open menu"
        trigger="hover"
      />,
    )

    const toggle = screen.getByRole('button', { name: 'Open menu' })
    await userEvent.hover(toggle)

    expect(screen.getByRole('button', { name: 'A' })).toBeInTheDocument()
  })

  it('does not open on hover when trigger is "click"', async () => {
    render(
      <RadialMenu
        items={[{ label: 'A' }]}
        toggleAriaLabel="Open menu"
        trigger="click"
      />,
    )

    await userEvent.hover(screen.getByRole('button', { name: 'Open menu' }))

    // The item button exists in the DOM (always mounted, opacity-animated) but isn't
    // interactive — assert the toggle itself never flips to its "open" state instead.
    expect(screen.getByRole('button', { name: 'Open menu' })).not.toHaveAttribute(
      'data-open',
      'true',
    )
  })
})
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd app
pnpm test radial-menu.test.tsx
```

Expected: FAIL — `radial-menu.tsx` doesn't exist yet.

- [ ] **Step 3: Implement `RadialMenu`**

Create `app/src/shared/ui/radial-menu.tsx`, porting forgekit's real `components/radial-menu.tsx` (same rotate+translateX circular-placement technique, same prop API) onto this repo's `Button` and StyleX tokens instead of forgekit's shadcn `Button` and Tailwind classes:

```tsx
import { create, props as stylexProps } from '@stylexjs/stylex'
import { Circle } from 'lucide-react'
import { motion } from 'motion/react'
import type { ReactNode } from 'react'
import { useState } from 'react'

import { radius } from '#/shared/lib/tokens.stylex'
import { Button } from './button'

const ORBIT_RADIUS = 72

const styles = create({
  container: {
    height: '2.25rem',
    position: 'relative',
    width: '2.25rem',
  },
  toggle: {
    borderRadius: radius.full,
    position: 'relative',
    zIndex: 60,
  },
  itemWrapper: {
    left: '50%',
    position: 'absolute',
    top: '50%',
    transform: 'translate(-50%, -50%)',
    zIndex: 50,
  },
  itemInner: {
    transform: 'translate(-50%, -50%)',
  },
  item: {
    borderRadius: radius.full,
    height: '2rem',
    minHeight: '2rem',
    minWidth: '2rem',
    width: '2rem',
  },
})

export interface RadialMenuItem {
  label: ReactNode
  onClick?: () => void
}

export interface RadialMenuProps {
  arc?: number
  startAngle?: number
  trigger?: 'hover' | 'click' | 'both'
  angles?: number[]
  items: RadialMenuItem[]
  toggle?: ReactNode
  toggleAriaLabel?: string
  radius?: number
}

/**
 * Ported from forgekit's real components/radial-menu.tsx — a generic, reusable radial
 * menu, not invented for this port. The circular placement is a rotate-then-translate
 * CSS composition trick: each item's outer wrapper is rotated to its target angle while
 * pinned to the toggle's center, then a plain inner div pushes it outward by a constant
 * radius along its own (now-rotated) local X axis — guaranteeing every item sits exactly
 * `radius` px from center regardless of angle, with no explicit sin/cos math. A second,
 * inner counter-rotation cancels the parent's rotation so the item's content renders
 * upright. Confirmed against forgekit's original before porting: no third-party geometry
 * dependency, just this transform-composition identity plus Motion's spring interpolation.
 */
export function RadialMenu({
  arc = 120,
  startAngle = 210,
  trigger = 'both',
  angles,
  items,
  toggle,
  toggleAriaLabel = 'Open menu',
  radius: radiusProp,
}: RadialMenuProps) {
  const [open, setOpen] = useState(false)

  const hoverEnabled = trigger !== 'click'
  const clickEnabled = trigger !== 'hover'

  const step = items.length > 1 ? arc / (items.length - 1) : 0
  const anglesList =
    angles && angles.length === items.length
      ? angles
      : items.map((_, i) => startAngle + step * i)
  const orbitRadius = typeof radiusProp === 'number' ? radiusProp : ORBIT_RADIUS

  const containerProps = stylexProps(styles.container)
  const toggleProps = stylexProps(styles.toggle)
  const itemWrapperProps = stylexProps(styles.itemWrapper)
  const itemInnerProps = stylexProps(styles.itemInner)
  const itemProps = stylexProps(styles.item)

  return (
    <div className={containerProps.className} style={containerProps.style}>
      <Button
        variant="ghost"
        size="icon"
        aria-label={toggleAriaLabel}
        data-open={open}
        className={toggleProps.className}
        style={toggleProps.style}
        onClick={() => {
          if (clickEnabled) setOpen((value) => !value)
        }}
        onMouseEnter={() => {
          if (hoverEnabled) setOpen(true)
        }}
        onMouseLeave={() => {
          if (hoverEnabled) setOpen(false)
        }}
      >
        {toggle ?? <Circle />}
      </Button>

      {items.map((item, index) => {
        const angle = anglesList[index] ?? startAngle
        return (
          // eslint-disable-next-line react/no-array-index-key -- items are positional, not identity-bearing
          <motion.div
            key={index}
            className={itemWrapperProps.className}
            style={{ ...itemWrapperProps.style, pointerEvents: open ? 'auto' : 'none' }}
            initial={{ rotate: 0, opacity: 0 }}
            animate={open ? { rotate: angle, opacity: 1 } : { rotate: 0, opacity: 0 }}
            transition={{ type: 'spring', stiffness: 360, damping: 26, delay: index * 0.05 }}
          >
            <div style={{ transform: `translateX(${orbitRadius}px)` }}>
              <motion.div
                className={itemInnerProps.className}
                style={{ ...itemInnerProps.style, rotate: -angle }}
              >
                <Button
                  variant="outline"
                  className={itemProps.className}
                  style={itemProps.style}
                  onClick={() => {
                    item.onClick?.()
                    setOpen(false)
                  }}
                >
                  {item.label}
                </Button>
              </motion.div>
            </div>
          </motion.div>
        )
      })}
    </div>
  )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd app
pnpm test radial-menu.test.tsx
```

Expected: PASS, all 4 cases.

- [ ] **Step 5: Manual visual spike — `motion` + StyleX combination**

This plan's spec flags `motion` + StyleX as an untested combination in this repo. Before trusting the automated tests alone, run `pnpm dev`, visit any page that will mount a `RadialMenu` (Task 5 wires the real consumer — for this spike, temporarily render `<RadialMenu items={[{label:'A'},{label:'B'},{label:'C'}]} />` directly inside `pages/sign-in/ui/sign-in-page.tsx`, check it opens/animates correctly in a real browser, then remove the temporary render). Confirm: the toggle is a visible circle, clicking fans out three circular items with a spring animation, each item's label renders upright (not tilted), items collapse back on click. Note any visual issue in the task report; do not silently proceed past a broken animation.

- [ ] **Step 6: Run the full check suite**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm test
pnpm build
```

Expected: all pass/succeed.

- [ ] **Step 7: Commit**

```bash
git add app/src/shared/ui/radial-menu.tsx app/src/shared/ui/radial-menu.test.tsx
git commit -m "feat: add RadialMenu, ported from forgekit's generic radial-menu component"
```

---

### Task 5: `LocaleSwitcher`

**Files:**
- Create: `app/src/shared/i18n/ui/locale-switcher.tsx`
- Test: `app/src/shared/i18n/ui/locale-switcher.test.tsx`

**Interfaces:**
- Consumes: `RadialMenu`, `RadialMenuItem` (Task 4); `SUPPORTED_LOCALES`, `LOCALE_COOKIE`, `Locale` (Task 1).
- Produces: `LocaleSwitcher` (no props) — Task 7 mounts it on the sign-in/sign-up cards.

- [ ] **Step 1: Write the failing tests**

Create `app/src/shared/i18n/ui/locale-switcher.test.tsx`:

```tsx
import type * as ReactRouter from '@tanstack/react-router'
import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { LocaleSwitcher } from './locale-switcher'

const navigate = vi.fn()

vi.mock('@tanstack/react-router', async (importOriginal) => {
  const actual = await importOriginal<typeof ReactRouter>()
  return { ...actual, useRouter: () => ({ navigate }) }
})

afterEach(() => {
  cleanup()
  navigate.mockReset()
  document.cookie = 'forgekit-tanstack-start.locale=; expires=Thu, 01 Jan 1970 00:00:00 UTC'
})

describe('LocaleSwitcher', () => {
  it('renders one item per supported locale', async () => {
    render(<LocaleSwitcher />)
    await userEvent.click(screen.getByRole('button', { name: 'Change language' }))

    expect(screen.getByRole('button', { name: 'EN' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '中' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '한' })).toBeInTheDocument()
  })

  it('navigates to the same path with the new locale prefix on click', async () => {
    Object.defineProperty(window, 'location', {
      value: { pathname: '/sign-in' },
      writable: true,
    })

    render(<LocaleSwitcher />)
    await userEvent.click(screen.getByRole('button', { name: 'Change language' }))
    await userEvent.click(screen.getByRole('button', { name: '中' }))

    expect(navigate).toHaveBeenCalledWith({ to: '/zh-TW/sign-in' })
  })

  it('writes the locale cookie on switch', async () => {
    Object.defineProperty(window, 'location', {
      value: { pathname: '/sign-in' },
      writable: true,
    })

    render(<LocaleSwitcher />)
    await userEvent.click(screen.getByRole('button', { name: 'Change language' }))
    await userEvent.click(screen.getByRole('button', { name: '한' }))

    expect(document.cookie).toContain('forgekit-tanstack-start.locale=ko-KR')
  })
})
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd app
pnpm test locale-switcher.test.tsx
```

Expected: FAIL — `locale-switcher.tsx` doesn't exist yet.

- [ ] **Step 3: Implement `LocaleSwitcher`**

Create `app/src/shared/i18n/ui/locale-switcher.tsx`:

```tsx
import { useRouter } from '@tanstack/react-router'
import { Languages } from 'lucide-react'

import { RadialMenu } from '#/shared/ui/radial-menu'
import type { RadialMenuItem } from '#/shared/ui/radial-menu'
import { LOCALE_COOKIE, SUPPORTED_LOCALES } from '../config'
import type { Locale } from '../config'
import { withLocalePrefix, buildLocale } from '../build-locale'

const LOCALE_LABELS: Record<Locale, string> = {
  en: 'EN',
  'zh-TW': '中',
  'ko-KR': '한',
}

/**
 * Ported from forgekit's real components/locale-switcher.tsx — reads the current path,
 * strips any existing locale prefix, and re-prefixes it for the chosen locale, matching
 * the "as-needed" convention (no prefix for the default locale).
 */
export function LocaleSwitcher() {
  const router = useRouter()

  const handleLocaleChange = (locale: Locale) => {
    const { path: pathWithoutPrefix } = buildLocale(window.location.pathname, undefined, undefined)
    document.cookie = `${LOCALE_COOKIE}=${locale}; path=/; max-age=31536000`
    router.navigate({ to: withLocalePrefix(pathWithoutPrefix, locale) })
  }

  const items: RadialMenuItem[] = SUPPORTED_LOCALES.map((locale) => ({
    label: LOCALE_LABELS[locale],
    onClick: () => handleLocaleChange(locale),
  }))

  return (
    <RadialMenu
      items={items}
      toggle={<Languages />}
      toggleAriaLabel="Change language"
      trigger="click"
      arc={75}
      startAngle={340}
    />
  )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd app
pnpm test locale-switcher.test.tsx
```

Expected: PASS, all 3 cases.

- [ ] **Step 5: Run the full check suite**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm test
pnpm build
```

Expected: all pass/succeed.

- [ ] **Step 6: Commit**

```bash
git add app/src/shared/i18n/ui
git commit -m "feat: add LocaleSwitcher built on RadialMenu"
```

---

### Task 6: Translated validation-schema factories

**Files:**
- Modify: `app/src/features/auth/model/sign-in-schema.ts`
- Modify: `app/src/features/auth/model/sign-up-schema.ts`
- Modify: `app/src/features/auth/model/sign-in-schema.test.ts`
- Modify: `app/src/features/auth/model/sign-up-schema.test.ts`

**Interfaces:**
- Consumes: `TFunction` type from `i18next` (Task 1's dependency).
- Produces: `createSignInSchema(t: TFunction<'validation'>): typeof signInSchema`, `createSignUpSchema(t: TFunction<'validation'>): typeof signUpSchema` — Task 7 calls both. The existing plain `signInSchema`/`signUpSchema` exports are untouched, so every current caller keeps working unchanged through this task.

- [ ] **Step 1: Write the failing tests**

Add to the end of `app/src/features/auth/model/sign-in-schema.test.ts` (keep the existing three tests above this):

```typescript
import type { TFunction } from 'i18next'

import { createSignInSchema } from './sign-in-schema'

const stubT = ((key: string, options?: { min?: number }) =>
  options ? `${key}:${options.min}` : key) as unknown as TFunction<'validation'>

describe('createSignInSchema', () => {
  it('accepts a valid sign-in', () => {
    const result = createSignInSchema(stubT).safeParse({
      email: 'person@example.com',
      password: 'abcd1234',
    })
    expect(result.success).toBe(true)
  })

  it('uses the translated message for an invalid email', () => {
    const result = createSignInSchema(stubT).safeParse({
      email: 'not-an-email',
      password: 'abcd1234',
    })
    expect(result.success).toBe(false)
    expect(result.error?.issues[0]?.message).toBe('authenticate.email.invalid')
  })

  it('uses the translated, interpolated message for a short password', () => {
    const result = createSignInSchema(stubT).safeParse({
      email: 'person@example.com',
      password: 'abc123',
    })
    expect(result.success).toBe(false)
    expect(result.error?.issues[0]?.message).toBe('authenticate.password.min:8')
  })
})
```

Add to the end of `app/src/features/auth/model/sign-up-schema.test.ts`:

```typescript
import type { TFunction } from 'i18next'

import { createSignUpSchema } from './sign-up-schema'

const stubT = ((key: string, options?: { min?: number }) =>
  options ? `${key}:${options.min}` : key) as unknown as TFunction<'validation'>

describe('createSignUpSchema', () => {
  it('accepts a valid registration', () => {
    expect(createSignUpSchema(stubT).safeParse(valid).success).toBe(true)
  })

  it('uses the translated message for mismatched passwords', () => {
    const result = createSignUpSchema(stubT).safeParse({
      ...valid,
      confirmPassword: 'different1',
    })
    expect(result.success).toBe(false)
    expect(result.error?.issues[0]?.message).toBe('authenticate.confirmPassword.confirm')
  })

  it('uses the translated message for an empty name', () => {
    const result = createSignUpSchema(stubT).safeParse({ ...valid, name: '' })
    expect(result.success).toBe(false)
    expect(result.error?.issues[0]?.message).toBe('authenticate.name.required')
  })
})
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd app
pnpm test sign-in-schema.test.ts sign-up-schema.test.ts
```

Expected: FAIL — `createSignInSchema`/`createSignUpSchema` don't exist yet.

- [ ] **Step 3: Implement the factories**

Modify `app/src/features/auth/model/sign-in-schema.ts` — add the factory below the existing plain schema, don't touch the plain schema itself:

```typescript
import type { TFunction } from 'i18next'
import { z } from 'zod'

export const signInSchema = z.object({
  email: z.email('Invalid email address').min(1, 'Email is required'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
})

/**
 * The i18n-aware counterpart of signInSchema, matching forgekit's createSignInSchema(t)
 * shape exactly. sign-in-form.tsx (Task 7) switches to this; the plain schema above stays
 * as the non-translated fallback/reference shape sub-project 2 originally shipped.
 */
export const createSignInSchema = (t: TFunction<'validation'>) =>
  signInSchema.extend({
    email: z
      .email(t('authenticate.email.invalid'))
      .min(1, t('authenticate.email.required')),
    password: z
      .string()
      .min(8, t('authenticate.password.min', { min: 8 })),
  })

export type SignInInput = z.infer<typeof signInSchema>
```

Modify `app/src/features/auth/model/sign-up-schema.ts`:

```typescript
import type { TFunction } from 'i18next'
import { z } from 'zod'

const passwordsMatch = (data: { password: string; confirmPassword: string }) =>
  data.password === data.confirmPassword

export const signUpSchema = z
  .object({
    name: z.string().min(1, 'Name is required'),
    email: z.email('Invalid email address').min(1, 'Email is required'),
    password: z.string().min(8, 'Password must be at least 8 characters'),
    confirmPassword: z.string('Confirm password is required'),
  })
  .refine(passwordsMatch, {
    path: ['confirmPassword'],
    message: 'Passwords must match',
  })

/**
 * The i18n-aware counterpart of signUpSchema, matching forgekit's createSignUpSchema(t)
 * shape exactly. sign-up-form.tsx (Task 7) switches to this; the plain schema above stays
 * as the non-translated fallback/reference shape sub-project 2 originally shipped.
 */
export const createSignUpSchema = (t: TFunction<'validation'>) =>
  z
    .object({
      name: z.string().min(1, t('authenticate.name.required')),
      email: z
        .email(t('authenticate.email.invalid'))
        .min(1, t('authenticate.email.required')),
      password: z
        .string()
        .min(8, t('authenticate.password.min', { min: 8 })),
      confirmPassword: z.string(t('authenticate.confirmPassword.required')),
    })
    .refine(passwordsMatch, {
      path: ['confirmPassword'],
      message: t('authenticate.confirmPassword.confirm'),
    })

export type SignUpInput = z.infer<typeof signUpSchema>
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd app
pnpm test sign-in-schema.test.ts sign-up-schema.test.ts
```

Expected: PASS, all cases (3 original + 3 new for sign-in; 5 original + 3 new for sign-up).

- [ ] **Step 5: Run the full check suite**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm test
```

Expected: all pass. `signInSchema`/`signUpSchema`'s existing callers (`sign-in-form.tsx`/`sign-up-form.tsx`, untouched by this task) keep working exactly as before — this task is purely additive.

- [ ] **Step 6: Commit**

```bash
git add app/src/features/auth/model/sign-in-schema.ts app/src/features/auth/model/sign-in-schema.test.ts app/src/features/auth/model/sign-up-schema.ts app/src/features/auth/model/sign-up-schema.test.ts
git commit -m "feat: add i18n-aware factory shape to sign-in/sign-up validation schemas"
```

---

### Task 7: Wire translations + `LocaleSwitcher` into the sign-in/sign-up forms

**Files:**
- Modify: `app/src/features/auth/ui/sign-in-form.tsx`
- Modify: `app/src/features/auth/ui/sign-up-form.tsx`
- Modify: `app/src/features/auth/ui/sign-in-form.test.tsx`
- Modify: `app/src/features/auth/ui/sign-up-form.test.tsx`

**Interfaces:**
- Consumes: `createSignInSchema`, `createSignUpSchema` (Task 6); `LocaleSwitcher` (Task 5); `useTranslation` from `react-i18next` (Task 1's dependency).
- Produces: nothing later in this plan consumes — this is the last UI-facing task; Task 8 only verifies.

- [ ] **Step 1: Update `sign-in-form.tsx`**

Current content (confirmed against the repo before writing this task):

```tsx
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm } from 'react-hook-form'

import { Button } from '#/shared/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '#/shared/ui/card'
import { Field, FieldDescription, FieldGroup, FieldLabel } from '#/shared/ui/field'
import { Input } from '#/shared/ui/input'

import { useSignIn } from '../model/use-sign-in'
import { useSocialSignIn } from '../model/use-social-sign-in'
import { signInSchema } from '../model/sign-in-schema'
import type { SignInInput } from '../model/sign-in-schema'

export function SignInForm() {
  const signIn = useSignIn()
  const socialSignIn = useSocialSignIn()

  const form = useForm<SignInInput>({
    resolver: zodResolver(signInSchema),
    defaultValues: { email: '', password: '' },
  })
  // ...unchanged JSX below
```

Replace the imports and the schema/resolver wiring, and mount `LocaleSwitcher` beside the social sign-in button:

```tsx
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm } from 'react-hook-form'
import { useTranslation } from 'react-i18next'

import { Button } from '#/shared/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '#/shared/ui/card'
import { Field, FieldDescription, FieldGroup, FieldLabel } from '#/shared/ui/field'
import { Input } from '#/shared/ui/input'
import { LocaleSwitcher } from '#/shared/i18n/ui/locale-switcher'

import { useSignIn } from '../model/use-sign-in'
import { useSocialSignIn } from '../model/use-social-sign-in'
import { createSignInSchema } from '../model/sign-in-schema'
import type { SignInInput } from '../model/sign-in-schema'

export function SignInForm() {
  const signIn = useSignIn()
  const socialSignIn = useSocialSignIn()
  const { t } = useTranslation('validation')

  const form = useForm<SignInInput>({
    resolver: zodResolver(createSignInSchema(t)),
    defaultValues: { email: '', password: '' },
  })
```

And add `<LocaleSwitcher />` as a sibling of the existing social sign-in `Field`, right after `<CardTitle>Sign in</CardTitle>` closes (inside `CardHeader`, matching forgekit's placement of its switcher beside the card's own controls):

```tsx
      <CardHeader>
        <CardTitle>Sign in</CardTitle>
        <LocaleSwitcher />
      </CardHeader>
```

Everything else in the file (the rest of the `<CardContent>` JSX, `onSubmit`, the closing braces) stays exactly as it is today.

- [ ] **Step 2: Update `sign-up-form.tsx`**

Same pattern. Current imports/wiring:

```tsx
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm } from 'react-hook-form'

import { Button } from '#/shared/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '#/shared/ui/card'
import { Field, FieldDescription, FieldGroup, FieldLabel } from '#/shared/ui/field'
import { Input } from '#/shared/ui/input'

import { useSignUp } from '../model/use-sign-up'
import { signUpSchema } from '../model/sign-up-schema'
import type { SignUpInput } from '../model/sign-up-schema'

export function SignUpForm() {
  const signUp = useSignUp()

  const form = useForm<SignUpInput>({
    resolver: zodResolver(signUpSchema),
    defaultValues: { name: '', email: '', password: '', confirmPassword: '' },
  })
```

Replace with:

```tsx
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm } from 'react-hook-form'
import { useTranslation } from 'react-i18next'

import { Button } from '#/shared/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '#/shared/ui/card'
import { Field, FieldDescription, FieldGroup, FieldLabel } from '#/shared/ui/field'
import { Input } from '#/shared/ui/input'
import { LocaleSwitcher } from '#/shared/i18n/ui/locale-switcher'

import { useSignUp } from '../model/use-sign-up'
import { createSignUpSchema } from '../model/sign-up-schema'
import type { SignUpInput } from '../model/sign-up-schema'

export function SignUpForm() {
  const signUp = useSignUp()
  const { t } = useTranslation('validation')

  const form = useForm<SignUpInput>({
    resolver: zodResolver(createSignUpSchema(t)),
    defaultValues: { name: '', email: '', password: '', confirmPassword: '' },
  })
```

And add `<LocaleSwitcher />` beside the title:

```tsx
      <CardHeader>
        <CardTitle>Create an account</CardTitle>
        <LocaleSwitcher />
      </CardHeader>
```

Everything else in the file stays exactly as it is today.

- [ ] **Step 3: Update the two existing test assertions that assumed English hardcoded copy**

`sign-in-form.test.tsx`'s second test currently asserts `/invalid email address/i` — the real `en` validation copy for that key is `"Please enter a valid email address"`, not `"Invalid email address"`. Update it:

```typescript
    expect(await screen.findByText(/valid email address/i)).toBeInTheDocument()
```

`sign-up-form.test.tsx`'s second test currently asserts `/passwords must match/i` — the real `en` validation copy for that key is `"Password not matched"`. Update it:

```typescript
    expect(await screen.findByText(/password not matched/i)).toBeInTheDocument()
```

No other assertion in either file changes — every other string this test checks (button names, labels) comes from hardcoded JSX text, not the schema's error messages, and this task doesn't touch that JSX text.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd app
pnpm test sign-in-form.test.tsx sign-up-form.test.tsx
```

Expected: PASS, all cases (including the two updated assertions).

- [ ] **Step 5: Run the full check suite**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm test
pnpm build
```

Expected: all pass/succeed.

- [ ] **Step 6: Manually verify against a real dev server**

```bash
cd app
pnpm dev &
sleep 5

curl -s http://localhost:3000/sign-in | grep -o "Sign in" # English default
curl -s http://localhost:3000/zh-TW/sign-in | grep -o "登入" # zh-TW LocaleSwitcher item label + page still renders

kill %1
```

Expected: both greps find a match — confirms the form renders in the requested locale end-to-end (SSR, not just the isolated component tests).

- [ ] **Step 7: Commit**

```bash
git add app/src/features/auth/ui/sign-in-form.tsx app/src/features/auth/ui/sign-in-form.test.tsx app/src/features/auth/ui/sign-up-form.tsx app/src/features/auth/ui/sign-up-form.test.tsx
git commit -m "feat: wire translated validation and LocaleSwitcher into sign-in/sign-up forms"
```

---

### Task 8: Final verification

**Files:** none created or modified — verification only.

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces: nothing later in this plan consumes — this is the final task.

- [ ] **Step 1: Manually verify the full locale-prefixed redirect chain against a real dev server**

```bash
cd app
pnpm dev &
sleep 5

# Unauthenticated, non-default locale, protected route: must 307 to the SAME locale's sign-in
curl -s -i http://localhost:3000/ko-KR/dashboard | grep -i "^location\|^HTTP"

# Sign up a real user, then visit a locale-prefixed protected route with the resulting cookie
curl -s -i -X POST http://localhost:3000/api/auth/sign-up/email \
  -H "Content-Type: application/json" \
  -d '{"email":"i18n-verify@example.com","password":"i18n-verify-pw-123","name":"I18n Verify"}' \
  > /tmp/i18n-verify-signup.txt
COOKIE=$(grep -o 'forgekit-tanstack-start.session_token=[^;]*' /tmp/i18n-verify-signup.txt)
curl -s http://localhost:3000/ko-KR/dashboard -H "Cookie: $COOKIE" | grep -o "Welcome"

rm -f /tmp/i18n-verify-signup.txt
kill %1
```

Expected: the unauthenticated request's `location` header is `/ko-KR/sign-in` (locale prefix survives the ABAC redirect chain, proving Task 3's design goal end-to-end); the authenticated request's response body contains `Welcome` (the dashboard still renders correctly on a locale-prefixed path — `/dashboard`'s own route is unaffected by this plan, confirming no regression).

- [ ] **Step 2: Run the full test/check/lint/build suite**

```bash
cd app
pnpm test
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

Expected: all pass/succeed. `pnpm lint:fsd` reports "No problems found!" — no `insignificant-slice` finding, since `shared/i18n/` and `shared/ui/radial-menu.tsx` are both under the exempt `shared` layer.

- [ ] **Step 3: Run the full family-wide verification suite**

```bash
cd ..
pnpm verify
```

Expected: exits 0 — API, App (now including every test this plan added), OpenSpec, and Secrets all pass.

- [ ] **Step 4: Commit via branch and PR**

```bash
git checkout -b feat/i18n
git add -A
git commit -m "feat: complete i18n port (sub-project 3)

Closes out sub-project 3: full parity with forgekit's 3-locale set
(en/zh-TW/ko-KR) via react-i18next, locale-aware routing wired into
the existing ABAC guard without changing its interface, and a real
LocaleSwitcher (built on a ported RadialMenu primitive) proving the
whole system end-to-end from the sign-in/sign-up cards."
git push -u origin feat/i18n
gh pr create --title "feat: complete i18n port (sub-project 3)" --body "Closes out sub-project 3. Manually verified end-to-end against a real dev server: locale-prefixed redirects preserve their prefix through the ABAC guard's redirect chain, sign-in/sign-up render in the requested locale via SSR, dashboard is unaffected."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```
