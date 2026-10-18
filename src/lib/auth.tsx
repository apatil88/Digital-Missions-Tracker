import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import type { User } from '@supabase/supabase-js'
import { providerReachable, supabase } from './supabase'

export type MyContext = {
  user_id: string
  staff: { school_id: string; role: 'instructor' | 'admin' }[]
  families: { family_id: string }[]
}

type Status = 'loading' | 'unavailable' | 'anonymous' | 'authenticated'

type AuthValue = {
  status: Status
  user: User | null
  context: MyContext | null
  isStaff: boolean
  isAdmin: boolean
  signIn: (email: string, password: string) => Promise<{ error: string | null }>
  signOut: () => Promise<void>
  retry: () => void
}

const AuthCtx = createContext<AuthValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient()
  const [status, setStatus] = useState<Status>('loading')
  const [user, setUser] = useState<User | null>(null)
  const [context, setContext] = useState<MyContext | null>(null)
  const [attempt, setAttempt] = useState(0)
  const lastUserId = useRef<string | null>(null)

  const clearPrivateState = useCallback(() => {
    // Logout and account switch: drop every in-memory record.
    queryClient.clear()
    setContext(null)
  }, [queryClient])

  const load = useCallback(async () => {
    setStatus('loading')
    if (!(await providerReachable())) {
      setStatus('unavailable')
      return
    }
    const { data } = await supabase.auth.getSession()
    if (!data.session) {
      setUser(null)
      setStatus('anonymous')
      return
    }
    const { data: ctx, error } = await supabase.rpc('get_my_context')
    if (error || !ctx) {
      // An expired or revoked session is anonymous; anything else is unavailable.
      if (error?.code === 'PGRST301' || error?.code === '42501') {
        await supabase.auth.signOut()
        setUser(null)
        setStatus('anonymous')
      } else setStatus('unavailable')
      return
    }
    setUser(data.session.user)
    setContext(ctx as MyContext)
    lastUserId.current = data.session.user.id
    setStatus('authenticated')
  }, [])

  useEffect(() => {
    void load()
  }, [load, attempt])

  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      const nextId = session?.user.id ?? null
      if (event === 'SIGNED_OUT' || (lastUserId.current && nextId !== lastUserId.current)) {
        clearPrivateState()
        if (event === 'SIGNED_OUT') {
          setUser(null)
          setStatus('anonymous')
          lastUserId.current = null
        }
      }
    })
    return () => sub.subscription.unsubscribe()
  }, [clearPrivateState])

  const signIn = useCallback(
    async (email: string, password: string) => {
      if (!(await providerReachable())) return { error: 'The service is unavailable right now. Nothing was saved. Try again shortly.' }
      clearPrivateState()
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) return { error: 'The email or password is not correct.' }
      await load()
      return { error: null }
    },
    [clearPrivateState, load],
  )

  const signOut = useCallback(async () => {
    clearPrivateState()
    await supabase.auth.signOut()
    setUser(null)
    setStatus('anonymous')
    lastUserId.current = null
  }, [clearPrivateState])

  const value = useMemo<AuthValue>(
    () => ({
      status,
      user,
      context,
      isStaff: (context?.staff.length ?? 0) > 0,
      isAdmin: context?.staff.some((s) => s.role === 'admin') ?? false,
      signIn,
      signOut,
      retry: () => setAttempt((n) => n + 1),
    }),
    [status, user, context, signIn, signOut],
  )
  return <AuthCtx.Provider value={value}>{children}</AuthCtx.Provider>
}

export function useAuth() {
  const v = useContext(AuthCtx)
  if (!v) throw new Error('useAuth must be used inside AuthProvider')
  return v
}
