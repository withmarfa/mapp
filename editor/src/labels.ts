/** The words the page shows or speaks, which the app supplies from its String Catalog when the page loads.
 *  English stands in until then. */
export const labels = {
  note: 'Note',
  copy: 'Copy',
  addRow: 'Add Row',
  addColumn: 'Add Column',
  deleteRow: 'Delete Row',
  deleteColumn: 'Delete Column',
  alignLeft: 'Align Left',
  alignCenter: 'Align Center',
  alignRight: 'Align Right',
  row: 'Row',
  column: 'Column',
}

export type Labels = typeof labels

export function setLabels(next: Partial<Labels>): void {
  Object.assign(labels, next)
}
