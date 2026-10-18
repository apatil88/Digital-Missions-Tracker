// F00-R05 reusable components: labels, errors, text status, focus management.
import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { ErrorSummary, Field, StatusBadge } from './ui'

describe('F00-R05 shared components', () => {
  it('Field links label, hint and error for assistive technology', () => {
    render(<Field label="Display name" hint="1 to 60 characters" error="Enter a name." />)
    const input = screen.getByLabelText('Display name')
    expect(input.getAttribute('aria-invalid')).toBe('true')
    const described = input.getAttribute('aria-describedby') ?? ''
    expect(described.split(' ')).toHaveLength(2)
    expect(document.getElementById(described.split(' ')[1])?.textContent).toContain('Enter a name.')
  })

  it('ErrorSummary announces and takes focus when errors appear, linking to fields', () => {
    render(<ErrorSummary errors={[{ fieldId: 'email', message: 'Enter your email address.' }]} />)
    const alert = screen.getByRole('alert')
    expect(document.activeElement).toBe(alert)
    expect(screen.getByRole('link', { name: 'Enter your email address.' }).getAttribute('href')).toBe('#email')
  })

  it('ErrorSummary renders nothing without errors', () => {
    const { container } = render(<ErrorSummary errors={[]} />)
    expect(container.innerHTML).toBe("")
  })

  it('StatusBadge states are conveyed in text for every persisted state', () => {
    const labels = { not_started: 'Not started', in_progress: 'In progress', submitted: 'Submitted', needs_changes: 'Needs changes', approved: 'Approved' } as const
    for (const [state, label] of Object.entries(labels)) {
      const { unmount } = render(<StatusBadge state={state as keyof typeof labels} />)
      expect(screen.getByText(label)).toBeTruthy()
      unmount()
    }
  })
})
