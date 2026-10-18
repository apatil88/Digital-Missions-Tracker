// FR02-R06: an administrator enables or disables approved missions for assignment.
import { useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth'
import { command, createRequestKey } from '@/lib/api'
import { supabase } from '@/lib/supabase'
import { missionName, type Template } from '@/lib/cycles'
import { Button, EmptyState, LoadingState, Notice } from '@/components/ui'

export function AdminCatalog() {
  const { user } = useAuth()
  const queryClient = useQueryClient()
  const keys = useRef(createRequestKey())
  const [busyId, setBusyId] = useState<string | null>(null)
  const [result, setResult] = useState<{ tone: 'info' | 'warning'; text: string } | null>(null)

  const list = useQuery({
    queryKey: ['templates', user?.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('mission_templates')
        .select('id, type, version, enabled, approved_content, setting_version')
        .order('type')
        .order('version', { ascending: false })
      if (error) throw error
      return data as Template[]
    },
  })

  async function setEnabled(t: Template, enabled: boolean) {
    setBusyId(t.id)
    setResult(null)
    const res = await command('set_catalog_enabled', {
      p_template_id: t.id,
      p_enabled: enabled,
      p_expected_version: t.setting_version,
      p_request_id: keys.current.for(`${t.id}|${enabled}|${t.setting_version}`),
    })
    setBusyId(null)
    const label = `${missionName(t.type)} version ${t.version}`
    setResult(res.ok ? { tone: 'info', text: `${label} ${enabled ? 'enabled' : 'disabled'}.` } : { tone: 'warning', text: res.error.message })
    void queryClient.invalidateQueries({ queryKey: ['templates', user?.id] })
  }

  return (
    <div className="flex flex-col gap-4">
      <Link to="/admin/settings" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Back to settings
      </Link>
      <h1 className="text-2xl font-bold">Missions</h1>
      <p className="text-muted">Only missions with approved content can be enabled. Enabling a mission does not change work that is already assigned or submitted.</p>
      {result && <Notice tone={result.tone}>{result.text}</Notice>}
      {list.isPending && <LoadingState label="Loading missions" />}
      {list.isError && (
        <Notice tone="warning">
          We could not load missions.{' '}
          <Button variant="link" onClick={() => void list.refetch()}>
            Try again
          </Button>
        </Notice>
      )}
      {list.data && list.data.length === 0 && <EmptyState title="No missions are set up" />}
      <ul className="flex flex-col gap-2">
        {list.data?.map((t) => {
          const name = `${missionName(t.type)} version ${t.version}`
          return (
            <li key={t.id} className="flex flex-col gap-2 rounded-card border border-line bg-card p-4">
              <p className="text-lg font-semibold">{name}</p>
              <p className="text-sm text-muted">
                {t.enabled ? 'Enabled' : 'Disabled'} · {t.approved_content ? 'Content approved' : 'Content not approved'}
              </p>
              <div>
                {t.enabled ? (
                  <Button variant="secondary" disabled={busyId === t.id} onClick={() => void setEnabled(t, false)} aria-label={`Disable ${name}`}>
                    Disable
                  </Button>
                ) : (
                  <Button disabled={busyId === t.id || !t.approved_content} onClick={() => void setEnabled(t, true)} aria-label={`Enable ${name}`}>
                    Enable
                  </Button>
                )}
              </div>
              {!t.enabled && !t.approved_content && <p className="text-sm text-warning">This content has no approval, so it cannot be enabled.</p>}
            </li>
          )
        })}
      </ul>
    </div>
  )
}
