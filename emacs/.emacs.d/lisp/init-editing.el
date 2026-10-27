;;; init-editing.el --- Editing behavior and in-buffer tools -*- lexical-binding: t; -*-

(require 'subr-x)

;; Keep backups and auto-saves out of source directories.
(let ((backup-dir (expand-file-name "backups/" user-emacs-directory))
      (autosave-dir (expand-file-name "auto-saves/" user-emacs-directory)))
  (make-directory backup-dir t)
  (make-directory autosave-dir t)
  (setq backup-directory-alist `(("." . ,backup-dir))
        auto-save-file-name-transforms `((".*" ,autosave-dir t))
        backup-by-copying t
        version-control t
        kept-new-versions 6
        kept-old-versions 2
        delete-old-versions t))

(setq inhibit-startup-screen t
      use-short-answers t
      ring-bell-function #'ignore
      tab-always-indent 'complete
      read-extended-command-predicate #'command-completion-default-include-p
      compilation-scroll-output 'first-error
      large-file-warning-threshold (* 10 1000 1000))
(setq-default indent-tabs-mode nil
              tab-width 4)

;; Emacs normally remembers that an edit happened, even when the user types
;; text and then deletes it again.  Keep a lightweight saved-content baseline
;; so an exactly restored buffer becomes genuinely unmodified again.
(defvar-local lcw-saved-content-size nil
  "Character count of this buffer at its last read or save.")

(defvar-local lcw-saved-content-hash nil
  "Hash of this buffer's text at its last read or save.")

(defun lcw-buffer-content-hash ()
  "Return a SHA-256 hash of all text in the current buffer."
  (save-restriction
    (widen)
    (secure-hash 'sha256 (current-buffer) (point-min) (point-max))))

(defun lcw-clear-modified-if-content-restored (&rest _ignored)
  "Clear the modified flag when text matches the last saved baseline.
The cheap size test avoids hashing during ordinary insertion and deletion."
  (when (and buffer-file-name
             (buffer-modified-p)
             lcw-saved-content-hash
             (= (buffer-size) lcw-saved-content-size)
             (equal (lcw-buffer-content-hash) lcw-saved-content-hash))
    (set-buffer-modified-p nil)
    (force-mode-line-update)))

(defun lcw-record-saved-content ()
  "Record the current file buffer text as its saved baseline."
  (when buffer-file-name
    (setq-local lcw-saved-content-size (buffer-size)
                lcw-saved-content-hash (lcw-buffer-content-hash))))

(defun lcw-enable-content-restore-check ()
  "Enable saved-content comparison after edits in the current buffer."
  (add-hook 'after-change-functions
            #'lcw-clear-modified-if-content-restored nil t))

(defun lcw-disable-content-restore-check ()
  "Disable saved-content comparison after edits in the current buffer."
  (remove-hook 'after-change-functions
               #'lcw-clear-modified-if-content-restored t))

(defun lcw-read-local-file-content-state (file coding)
  "Return FILE's decoded (SIZE . HASH) using CODING.
This helper deliberately avoids reading remote files during configuration
reloads; remote buffers establish their baseline when opened or saved."
  (when (and file (not (file-remote-p file)) (file-readable-p file))
    (condition-case nil
        (let ((coding-system-for-read coding))
          (with-temp-buffer
            (insert-file-contents file)
            (cons (buffer-size) (lcw-buffer-content-hash))))
      (file-error nil))))

(defun lcw-initialize-saved-content-tracking (&optional buffer)
  "Install saved-content tracking in BUFFER, including after a reload."
  (with-current-buffer (or buffer (current-buffer))
    (when buffer-file-name
      (cond
       ((not (buffer-modified-p))
        (lcw-record-saved-content))
       ((not (file-remote-p buffer-file-name))
        (if-let* ((state
                   (lcw-read-local-file-content-state
                    buffer-file-name buffer-file-coding-system)))
            (setq-local lcw-saved-content-size (car state)
                        lcw-saved-content-hash (cdr state))
          ;; A newly created, not-yet-saved file has an empty disk baseline.
          (setq-local lcw-saved-content-size 0
                      lcw-saved-content-hash (secure-hash 'sha256 "")))
        (lcw-clear-modified-if-content-restored)))
      (lcw-enable-content-restore-check))))

(add-hook 'find-file-hook #'lcw-record-saved-content 95)
(add-hook 'after-save-hook #'lcw-record-saved-content 95)
(add-hook 'after-revert-hook #'lcw-record-saved-content 95)

;; Reloading this module should fix existing local buffers immediately without
;; opening a network connection for currently modified TRAMP buffers.
(dolist (buffer (buffer-list))
  (lcw-initialize-saved-content-tracking buffer))

(show-paren-mode 1)
(electric-pair-mode 1)
(delete-selection-mode 1)
(save-place-mode 1)
(savehist-mode 1)
(recentf-mode 1)
(global-auto-revert-mode 1)
(which-key-mode 1)
(editorconfig-mode 1)
(repeat-mode 1)
(setq display-line-numbers-type t
      display-line-numbers-width 3)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)
(add-hook 'text-mode-hook #'display-line-numbers-mode)
(add-hook 'prog-mode-hook #'hl-line-mode)

;; Protect the UI from pathological long lines and files too large to load whole.
(use-package so-long
  :ensure nil
  :config
  (global-so-long-mode 1))

(use-package vlf-setup
  :if (locate-library "vlf-setup")
  :demand t
  :bind (("C-c v" . vlf))
  :custom
  (vlf-application 'ask)
  (vlf-batch-size 1000000))

(use-package yasnippet
  :if (locate-library "yasnippet")
  :hook (prog-mode . yas-minor-mode)
  :custom
  (yas-snippet-dirs (list (expand-file-name "snippets" user-emacs-directory)))
  :config
  (yas-reload-all))

(defun lcw-add-cape-completions ()
  "Add file and buffer-word completion as fallbacks in this buffer."
  (add-hook 'completion-at-point-functions #'cape-file 90 t)
  (add-hook 'completion-at-point-functions #'cape-dabbrev 100 t))

(use-package cape
  :if (locate-library "cape")
  :hook ((prog-mode . lcw-add-cape-completions)
         (text-mode . lcw-add-cape-completions)))

(use-package multiple-cursors
  :if (locate-library "multiple-cursors")
  :bind (("C->" . mc/mark-next-like-this)
         ("C-<" . mc/mark-previous-like-this)
         ("C-c C-<" . mc/mark-all-like-this)
         ("C-S-c C-S-c" . mc/edit-lines)
         ("C-\"" . mc/skip-to-next-like-this)
         ("C-:" . mc/skip-to-previous-like-this))
  :custom
  (mc/list-file (expand-file-name "state/multiple-cursors-lists.el"
                                   user-emacs-directory)))

(use-package paredit
  :if (locate-library "paredit")
  :commands paredit-mode)

;; Emacs 30 Corfu popups need a graphical frame. Terminals retain built-in
;; completion (C-M-i / TAB), without requiring a terminal popup extension.
(defun lcw-enable-corfu-in-gui ()
  "Enable Corfu for graphical programming buffers."
  (when (display-graphic-p)
    (corfu-mode 1)))

(use-package corfu
  :if (locate-library "corfu")
  :hook (prog-mode . lcw-enable-corfu-in-gui)
  :custom
  (corfu-cycle t)
  (corfu-auto nil)
  (corfu-preview-current nil)
  :config
  (corfu-popupinfo-mode 1))

(keymap-global-set "C-," #'duplicate-dwim)

;; Markdown remains a portable editing format; Obsidian manages the vault.
(require 'cl-lib)

(defun lcw-markdown-limit-wiki-search ()
  "Recognize wiki links without recursively scanning large repositories."
  (setq-local markdown-wiki-link-search-type nil
              markdown-wiki-link-search-subdirectories nil
              markdown-wiki-link-search-parent-directories nil))

(defface lcw-markdown-table-preview-border-face
  '((t :inherit (fixed-pitch font-lock-comment-face)))
  "Face used for Markdown table borders."
  :group 'markdown-faces)

(defface lcw-markdown-table-preview-header-face
  '((t :inherit (fixed-pitch bold markdown-table-face)))
  "Face used for Markdown table headers."
  :group 'markdown-faces)

(defvar-local lcw-markdown-table-preview--overlays nil)
(defvar-local lcw-markdown-table-preview--tables nil)
(defvar-local lcw-markdown-table-preview--active-table nil)
(defvar-local lcw-markdown-table-preview--tick -1)
(defvar-local lcw-markdown-table-preview--window-pixel-width nil)
(defvar-local lcw-markdown-table-preview--refreshing nil)
(defvar-local lcw-markdown-highlighting-keywords-installed nil)

(defun lcw-markdown-enable-obsidian-highlights ()
  "Render nested Obsidian `==highlight==' markup reliably.
Markdown Mode's built-in highlighter recognizes the delimiters, but a nested
construct such as `==text **strong** text==' loses the highlight face when the
strong-emphasis rule runs later.  Reapply only the highlight face with append
semantics, leaving all nested faces intact."
  (unless lcw-markdown-highlighting-keywords-installed
    (font-lock-add-keywords
     nil
     `((,markdown-regex-highlighting
        (4 'markdown-highlighting-face append)))
     'append)
    (setq-local lcw-markdown-highlighting-keywords-installed t)
    (font-lock-flush)))

(defun lcw-markdown-table-preview--split-row (line)
  "Return the cells in Markdown table LINE.
Leading and trailing pipes are treated as borders, and escaped pipes do not
split a cell."
  (let* ((text (string-trim line))
         (text (if (string-prefix-p "|" text) (substring text 1) text))
         (text (if (string-suffix-p "|" text)
                   (substring text 0 -1)
                 text))
         (start 0)
         cells)
    (dotimes (index (length text))
      (when (and (= (aref text index) ?|)
                 (or (= index 0) (/= (aref text (1- index)) ?\\)))
        (push (string-trim (substring text start index)) cells)
        (setq start (1+ index))))
    (push (string-trim (substring text start)) cells)
    (nreverse cells)))

(defun lcw-markdown-table-preview--separator-p (cells)
  "Return non-nil when CELLS form a GFM table separator row."
  (and (>= (length cells) 2)
       (cl-every
        (lambda (cell)
          (string-match-p "\\`:?-\\{3,\\}:?\\'" cell))
        cells)))

(defun lcw-markdown-table-preview--line-info ()
  "Describe the current line for the Markdown table previewer."
  (let* ((begin (line-beginning-position))
         (end (line-end-position))
         (text (buffer-substring-no-properties begin end)))
    (list :begin begin
          :end end
          :text text
          :indent (if (string-match "\\`[ \t]*" text)
                      (match-string 0 text)
                    "")
          :cells (and (string-match-p "|" text)
                      (lcw-markdown-table-preview--split-row text)))))

(defun lcw-markdown-table-preview--scan ()
  "Return the GFM pipe tables in the current buffer."
  (save-excursion
    (goto-char (point-min))
    (let (tables)
      (while (not (eobp))
        (let* ((separator (lcw-markdown-table-preview--line-info))
               (separator-cells (plist-get separator :cells)))
          (if (and separator-cells
                   (lcw-markdown-table-preview--separator-p separator-cells)
                   (> (line-beginning-position) (point-min)))
              (let ((separator-column-count (length separator-cells))
                    header rows table-end)
                (save-excursion
                  (forward-line -1)
                  (setq header (lcw-markdown-table-preview--line-info)))
                (if (not (= (length (or (plist-get header :cells) '()))
                            separator-column-count))
                    (forward-line 1)
                  (setq rows (list header)
                        table-end (plist-get separator :end))
                  (save-excursion
                    (forward-line 1)
                    (while (not (eobp))
                      (let* ((row (lcw-markdown-table-preview--line-info))
                             (cells (plist-get row :cells)))
                        (if (and cells
                                 (= (length cells) separator-column-count)
                                 (not (lcw-markdown-table-preview--separator-p
                                       cells)))
                            (progn
                              (setq rows (append rows (list row))
                                    table-end (plist-get row :end))
                              (forward-line 1))
                          (goto-char (point-max))))))
                  (push (list :start (plist-get header :begin)
                              :end table-end
                              :indent (plist-get header :indent)
                              :separator separator
                              :separator-cells separator-cells
                              :rows rows)
                        tables)
                  (goto-char (min (point-max) (1+ table-end)))))
            (forward-line 1))))
      (nreverse tables))))

(defun lcw-markdown-table-preview--alignment (separator-cell)
  "Return the alignment requested by SEPARATOR-CELL."
  (cond
   ((and (string-prefix-p ":" separator-cell)
         (string-suffix-p ":" separator-cell))
    'center)
   ((string-suffix-p ":" separator-cell) 'right)
   (t 'left)))

(defun lcw-markdown-table-preview--inline (text face)
  "Render strong and highlighted inline Markdown in TEXT using FACE.
Table rows are display strings and cannot reuse the source buffer's font-lock
properties.  Parse the two presentation constructs explicitly so nested forms
such as `==text **strong** text==' retain both faces without showing markers."
  (let ((position 0)
        pieces)
    (while (string-match "\\(\\*\\*\\|==\\)" text position)
      (let* ((open-begin (match-beginning 0))
             (open-end (match-end 0))
             (delimiter (match-string 0 text))
             (close (string-match (regexp-quote delimiter) text open-end)))
        (if (not close)
            (progn
              (push (propertize (substring text position) 'face face) pieces)
              (setq position (length text)))
          (push (propertize (substring text position open-begin)
                            'face face)
                pieces)
          (let* ((added-face
                  (if (equal delimiter "**")
                      'bold
                    'markdown-highlighting-face))
                 (nested-face
                  (cons added-face
                        (if (listp face) face (list face)))))
            (push (lcw-markdown-table-preview--inline
                   (substring text open-end close) nested-face)
                  pieces))
          (setq position (+ close (length delimiter))))))
    (push (propertize (substring text position) 'face face) pieces)
    (apply #'concat (nreverse pieces))))

(defun lcw-markdown-table-preview--pixel-width (string)
  "Return the displayed pixel width of STRING with a safe fallback."
  (if (fboundp 'string-pixel-width)
      (condition-case nil
          (string-pixel-width string)
        (error (* (string-width string) (max 1 (frame-char-width)))))
    (* (string-width string) (max 1 (frame-char-width)))))

(defun lcw-markdown-table-preview--display-window ()
  "Return the window whose width should constrain the current table.
Dirvish runs its preview hook before installing the preview buffer in the
preview window, so consult the current Dirvish session as a fallback."
  (or (get-buffer-window (current-buffer) t)
      (when (and (fboundp 'dirvish--get-session)
                 (fboundp 'dv-preview-window))
        (when-let* ((session (ignore-errors (dirvish--get-session)))
                    (window (dv-preview-window session))
                    ((window-live-p window)))
          window))
      (selected-window)))

(defun lcw-markdown-table-preview--fit-widths (widths budget unit)
  "Fit pixel WIDTHS within BUDGET, preserving UNIT-sized boundaries.
Each column receives room for two padding units and, when possible, one unit
of content.  Remaining space is distributed in proportion to natural width."
  (let* ((count (length widths))
         (natural (mapcar (lambda (width) (ceiling width unit)) widths))
         (budget-units (max count (floor budget unit))))
    (if (<= (apply #'+ natural) budget-units)
        widths
      (let* ((minimum (if (>= budget-units (* count 3))
                          3
                        (max 1 (/ budget-units count))))
             (extra-budget (max 0 (- budget-units (* count minimum))))
             (needs (mapcar (lambda (width) (max 0 (- width minimum)))
                            natural))
             (total-need (apply #'+ needs))
             (fitted
              (mapcar
               (lambda (need)
                 (+ minimum
                    (if (zerop total-need)
                        0
                      (/ (* extra-budget need) total-need))))
               needs))
             (remaining (- budget-units (apply #'+ fitted))))
        ;; Integer division leaves fewer than COUNT units undistributed.
        (while (> remaining 0)
          (let ((changed nil))
            (cl-loop for tail on fitted
                     for natural-width in natural
                     when (and (> remaining 0)
                               (< (car tail) natural-width))
                     do (setcar tail (1+ (car tail)))
                     (setq remaining (1- remaining)
                           changed t))
            (unless changed
              (setq remaining 0))))
        (mapcar (lambda (width) (* width unit)) fitted)))))

(defun lcw-markdown-table-preview--truncate-cell (cell max-pixels)
  "Truncate rendered CELL with an ellipsis to fit MAX-PIXELS."
  (if (<= (lcw-markdown-table-preview--pixel-width cell) max-pixels)
      cell
    (let* ((face (and (> (length cell) 0)
                      (get-text-property 0 'face cell)))
           (ellipsis (propertize "…" 'face face))
           (ellipsis-width
            (lcw-markdown-table-preview--pixel-width ellipsis))
           (limit (- max-pixels ellipsis-width))
           (low 0)
           (high (length cell)))
      (if (< limit 0)
          ""
        (while (< low high)
          (let ((middle (/ (+ low high 1) 2)))
            (if (<= (lcw-markdown-table-preview--pixel-width
                     (substring cell 0 middle))
                    limit)
                (setq low middle)
              (setq high (1- middle)))))
        (concat (substring cell 0 low) ellipsis)))))

(defun lcw-markdown-table-preview--pixel-space (pixels)
  "Return a display string occupying exactly PIXELS horizontal pixels."
  (if (> pixels 0)
      (propertize " " 'display `(space :width (,pixels))
                  'face 'fixed-pitch)
    ""))

(defun lcw-markdown-table-preview--pad-cell (cell width alignment unit)
  "Pad rendered CELL to pixel WIDTH according to ALIGNMENT.
UNIT is one canonical fixed-pitch character in pixels."
  (let* ((content-width (lcw-markdown-table-preview--pixel-width cell))
         (space (max 0 (- width content-width (* 2 unit))))
         (left-extra (pcase alignment
                       ('right space)
                       ('center (/ space 2))
                       (_ 0)))
         (right-extra (- space left-extra)))
    (concat (lcw-markdown-table-preview--pixel-space (+ unit left-extra))
            cell
            (lcw-markdown-table-preview--pixel-space (+ unit right-extra)))))

(defun lcw-markdown-table-preview--add-overlay (begin end &rest properties)
  "Create and remember a table preview overlay from BEGIN to END."
  (let ((overlay (make-overlay begin end nil t nil)))
    (overlay-put overlay 'lcw-markdown-table-preview t)
    ;; Zero-width overlays carry the virtual top and bottom borders.  Giving
    ;; those overlays `evaporate' would delete them as soon as they are made.
    (when (< begin end)
      (overlay-put overlay 'evaporate t))
    (while properties
      (overlay-put overlay (pop properties) (pop properties)))
    (push overlay lcw-markdown-table-preview--overlays)
    overlay))

(defun lcw-markdown-table-preview--rule (left middle right widths unit)
  "Build a table rule using LEFT, MIDDLE, RIGHT, WIDTHS, and pixel UNIT."
  (concat left
          (mapconcat (lambda (width) (make-string (/ width unit) ?─))
                     widths middle)
          right))

(defun lcw-markdown-table-preview--render (table)
  "Render TABLE with display-only Unicode borders."
  (let* ((rows (plist-get table :rows))
         (separator (plist-get table :separator))
         (separator-cells (plist-get table :separator-cells))
         (column-count (length separator-cells))
         (alignments (mapcar #'lcw-markdown-table-preview--alignment
                             separator-cells))
         (unit (max 1 (frame-char-width)))
         (raw-rendered-rows
          (cl-loop for row in rows
                   for first = t then nil
                   for face = (if first
                                  '(lcw-markdown-table-preview-header-face
                                    fixed-pitch)
                                '(markdown-table-face fixed-pitch))
                   collect
                   (mapcar (lambda (cell)
                             (lcw-markdown-table-preview--inline cell face))
                           (plist-get row :cells))))
         (natural-widths
          (cl-loop for column below column-count
                   collect
                   (let ((needed
                          (+ (* 2 unit)
                             (cl-loop for cells in raw-rendered-rows
                                      maximize
                                      (lcw-markdown-table-preview--pixel-width
                                       (nth column cells))))))
                     ;; Box-drawing glyphs occupy one canonical character.
                     ;; Rounding makes every junction land on a glyph edge.
                     (* unit (ceiling needed unit)))))
         (indent (plist-get table :indent))
         (window (lcw-markdown-table-preview--display-window))
         (window-width (if (window-live-p window)
                           (window-body-width window t)
                         (* 100 unit)))
         ;; Leave one character of slack so redisplay never wraps a virtual
         ;; border because of rounding at the right edge.
         (column-budget
          (max (* column-count unit)
               (- window-width
                  (lcw-markdown-table-preview--pixel-width indent)
                  (* (+ column-count 2) unit))))
         (widths
          (lcw-markdown-table-preview--fit-widths
           natural-widths column-budget unit))
         (rendered-rows
          (mapcar
           (lambda (cells)
             (cl-mapcar
              (lambda (cell width)
                (lcw-markdown-table-preview--truncate-cell
                 cell (max unit (- width (* 2 unit)))))
              cells widths))
           raw-rendered-rows))
         (top (lcw-markdown-table-preview--rule "┌" "┬" "┐" widths unit))
         (middle (lcw-markdown-table-preview--rule "├" "┼" "┤" widths unit))
         (bottom (lcw-markdown-table-preview--rule "└" "┴" "┘" widths unit))
         (vertical (propertize "│"
                              'face 'lcw-markdown-table-preview-border-face)))
    (setq lcw-markdown-table-preview--window-pixel-width window-width)
    (cl-loop for row in rows
             for cells in rendered-rows
             for first = t then nil
             do
             (let ((rendered
                    (concat indent vertical
                            (mapconcat
                             #'identity
                             (cl-mapcar #'lcw-markdown-table-preview--pad-cell
                                        cells widths alignments
                                        (make-list column-count unit))
                             vertical)
                            vertical)))
               (lcw-markdown-table-preview--add-overlay
                (plist-get row :begin) (plist-get row :end)
                ;; A display string used as an overlay's replacement ignores
                ;; display properties nested inside that string.  Put the
                ;; rendered row in `before-string' instead, and replace the
                ;; source with an empty display.  Pixel-width spaces are then
                ;; honored by the actual redisplay engine.
                'display ""
                'before-string
                (if first
                    (concat
                     (propertize (concat indent top "\n")
                                 'face
                                 'lcw-markdown-table-preview-border-face)
                     rendered)
                  rendered))))
    (lcw-markdown-table-preview--add-overlay
     (plist-get separator :begin) (plist-get separator :end)
     'display ""
     'before-string
     (propertize (concat indent middle)
                 'face 'lcw-markdown-table-preview-border-face))
    (lcw-markdown-table-preview--add-overlay
     (plist-get table :end) (plist-get table :end)
     'after-string
     (propertize (concat "\n" indent bottom)
                 'face 'lcw-markdown-table-preview-border-face))))

(defun lcw-markdown-table-preview--clear ()
  "Remove all table preview overlays from the current buffer."
  ;; Also remove tagged orphans.  Redisplay and window-change hooks can run
  ;; while a preview is being rebuilt; older versions could consequently lose
  ;; one overlay set from the tracking list and draw a table twice.
  (dolist (overlay (overlays-in (point-min) (point-max)))
    (when (overlay-get overlay 'lcw-markdown-table-preview)
      (delete-overlay overlay)))
  (mapc #'delete-overlay lcw-markdown-table-preview--overlays)
  (setq lcw-markdown-table-preview--overlays nil))

(defun lcw-markdown-table-preview--table-at-point (tables)
  "Return the member of TABLES containing point."
  (cl-find-if (lambda (table)
                (and (<= (plist-get table :start) (point))
                     (<= (point) (1+ (plist-get table :end)))))
              tables))

(defun lcw-markdown-table-preview-refresh (&optional force)
  "Refresh in-buffer Markdown table previews.
With FORCE, rebuild previews even when neither text nor point context changed."
  (when (and lcw-markdown-table-preview-mode
             (not lcw-markdown-table-preview--refreshing))
    (let ((lcw-markdown-table-preview--refreshing t))
      (let* ((tick (buffer-chars-modified-tick))
             (text-changed (/= tick lcw-markdown-table-preview--tick))
             (tables (if text-changed
                         (lcw-markdown-table-preview--scan)
                       lcw-markdown-table-preview--tables))
             (active (lcw-markdown-table-preview--table-at-point tables)))
        (when (or force text-changed
                  (not (equal active
                              lcw-markdown-table-preview--active-table)))
          (lcw-markdown-table-preview--clear)
          (setq lcw-markdown-table-preview--tables tables
                lcw-markdown-table-preview--active-table active
                lcw-markdown-table-preview--tick tick)
          (dolist (table tables)
            ;; Reveal the source of the table being edited.  Other tables stay
            ;; rendered, like anti-conceal behavior in live-preview editors.
            (unless (equal table active)
              (lcw-markdown-table-preview--render table))))))))

(defun lcw-markdown-table-preview-refresh-visible-windows ()
  "Reflow visible table previews whose window width has changed."
  (dolist (window (window-list (selected-frame) 'nomini))
    (when (window-live-p window)
      (with-current-buffer (window-buffer window)
        (when lcw-markdown-table-preview-mode
          (let ((width (window-body-width window t)))
            (unless (equal width
                           lcw-markdown-table-preview--window-pixel-width)
              (setq lcw-markdown-table-preview--window-pixel-width width)
              (lcw-markdown-table-preview-refresh t))))))))

(add-hook 'window-configuration-change-hook
          #'lcw-markdown-table-preview-refresh-visible-windows)

(define-minor-mode lcw-markdown-table-preview-mode
  "Render GFM pipe tables in place while keeping their source editable."
  :lighter " Tbl"
  (if lcw-markdown-table-preview-mode
      (progn
        (add-hook 'post-command-hook
                  #'lcw-markdown-table-preview-refresh nil t)
        (lcw-markdown-table-preview-refresh t))
    (remove-hook 'post-command-hook
                 #'lcw-markdown-table-preview-refresh t)
    (lcw-markdown-table-preview--clear)
    (setq lcw-markdown-table-preview--tables nil
          lcw-markdown-table-preview--active-table nil
          lcw-markdown-table-preview--tick -1
          lcw-markdown-table-preview--window-pixel-width nil)))

(defun lcw-markdown-pretty ()
  "Use a more Obsidian-like Markdown display."
  (visual-line-mode 1)
  (lcw-markdown-enable-obsidian-highlights)
  (when (display-images-p)
    (markdown-display-inline-images)))

(defun lcw-markdown-dirvish-preview-setup ()
  "Apply the normal Markdown presentation to a Dirvish preview buffer.
Dirvish intentionally skips major-mode hooks while preparing previews, so
the regular `gfm-mode-hook' setup must be applied from its preview hook."
  (when (derived-mode-p 'markdown-mode)
    (lcw-markdown-limit-wiki-search)
    (lcw-markdown-pretty)
    (lcw-markdown-table-preview-mode 1)))

(with-eval-after-load 'dirvish
  (add-hook 'dirvish-preview-setup-hook
            #'lcw-markdown-dirvish-preview-setup))

(use-package markdown-mode
  :if (locate-library "markdown-mode")
  :mode (("\\.\\(?:md\\|markdown\\)\\'" . gfm-mode))
  :hook ((gfm-mode . lcw-markdown-limit-wiki-search)
         (gfm-mode . lcw-markdown-pretty)
         (gfm-mode . lcw-markdown-table-preview-mode))
  :bind (:map markdown-mode-map
              ("C-c C-x t" . lcw-markdown-table-preview-mode))
  :custom
  (markdown-fontify-code-blocks-natively t)
  (markdown-enable-wiki-links t)
  (markdown-enable-math t)
  (markdown-enable-highlighting-syntax t)
  (markdown-hide-markup t)
  (markdown-hide-urls t)
  (markdown-header-scaling t)
  :config
  ;; markdown-mode registers a generic .md rule while loading. Keep GFM first.
  (let ((entry '("\\.\\(?:md\\|markdown\\)\\'" . gfm-mode)))
    (setq auto-mode-alist (delete entry auto-mode-alist))
    (push entry auto-mode-alist)))

;; PDF Tools loads when a PDF is opened and never invokes a system package manager.
(use-package pdf-tools
  :if (locate-library "pdf-tools")
  :defer t
  :init
  (setq pdf-view-display-size 'fit-width)
  (pdf-loader-install nil t)
  :hook (pdf-view-mode . (lambda () (display-line-numbers-mode -1))))

(provide 'init-editing)
;;; init-editing.el ends here
