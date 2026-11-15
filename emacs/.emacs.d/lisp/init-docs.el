;;; init-docs.el --- Long-form documents: Markdown, Typst and PDF -*- lexical-binding: t; -*-

(declare-function pdf-loader-install "pdf-tools.el")

;; Document formats that behave like reading surfaces rather than code.
;; The Dirvish preview hook lives here too: the Markdown presentation must
;; be applied from inside Dirvish (owned by init-project) because preview
;; buffers deliberately skip major-mode hooks.

;; Markdown remains a portable editing format; Obsidian manages the vault.
(require 'bindat)
(require 'cl-lib)
(require 'project)
(require 'treesit)

(defun lcw-markdown-limit-wiki-search ()
  "Recognize wiki links without recursively scanning large repositories."
  (setq-local markdown-wiki-link-search-type nil
              markdown-wiki-link-search-subdirectories nil
              markdown-wiki-link-search-parent-directories nil))

;; Table layout uses gfm-mode-hook, Markdown faces, and Emacs overlays.
;; After an Emacs upgrade, check wrapping and border alignment with line
;; numbers enabled and in split windows.

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
(defvar-local lcw-markdown-table-preview--active-row nil)
(defvar-local lcw-markdown-table-preview--tick -1)
(defvar-local lcw-markdown-table-preview--geometry nil)
(defvar-local lcw-markdown-table-preview--refreshing nil)
(defvar lcw-markdown-table-preview-mode)
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
                                 (not (lcw-markdown-table-preview--separator-p
                                       cells)))
                            (progn
                              (push row rows)
                              (setq table-end (plist-get row :end))
                              (forward-line 1))
                          (goto-char (point-max))))))
                  (push (list :end table-end
                              :indent (plist-get header :indent)
                              :separator separator
                              :separator-cells separator-cells
                              :rows (nreverse rows))
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

(defun lcw-markdown-table-preview--window-size (window)
  "Return WINDOW's usable text width and character width in pixels."
  (let ((unit (max 1 (frame-char-width (window-frame window))))
        (gutter (if (and display-line-numbers
                         (eq (window-buffer window) (current-buffer)))
                    (with-selected-window window (line-number-display-width t))
                  0)))
    ;; The body width includes the gutter and the continuation column.
    (cons (- (window-body-width window t) gutter unit) unit)))

(defun lcw-markdown-table-preview--measure ()
  "Choose a layout that fits every window showing this buffer."
  (let ((windows (or (get-buffer-window-list (current-buffer) 'nomini 'visible)
                     (list (lcw-markdown-table-preview--display-window))))
        smallest)
    (dolist (window windows smallest)
      (let ((size (lcw-markdown-table-preview--window-size window)))
        (when (or (not smallest) (< (car size) (car smallest)))
          (setq smallest size))))))

(defun lcw-markdown-table-preview--fit-widths (widths budget unit)
  "Fit pixel WIDTHS within BUDGET, preserving UNIT-sized boundaries.
Keep short columns at their natural width and share space among long columns."
  (let* ((natural (mapcar (lambda (width) (ceiling width unit)) widths))
         (budget-units (floor budget unit)))
    (if (<= (apply #'+ natural) budget-units)
        widths
      (let ((sorted (sort (copy-sequence natural) #'<))
            (available budget-units)
            (remaining (length natural)))
        (while (and (cdr sorted) (<= (car sorted) (/ available remaining)))
          (cl-decf available (pop sorted))
          (cl-decf remaining))
        (let ((share (/ available remaining))
              (extra (% available remaining)))
          (mapcar (lambda (width)
                    (* unit (cond
                             ((<= width share) width)
                             ((> extra 0)
                              (cl-decf extra)
                              (1+ share))
                             (t share))))
                  natural))))))

(defun lcw-markdown-table-preview--fragment-end (cell offsets start limit)
  "Find the last glyph boundary in CELL that fits LIMIT pixels from START.
START and the result index the glyph boundaries in OFFSETS."
  (let* ((begin (aref offsets start))
         (last (1- (length offsets)))
         (low start)
         (high (1+ start)))
    ;; Probe only the next fragment, even for a cell spanning many lines.
    (cl-labels ((fits (end)
                  (<= (lcw-markdown-table-preview--pixel-width
                       (substring cell begin (aref offsets end)))
                      limit)))
      (while (and (< high last) (fits high))
        (setq low high
              high (min last (+ start (* 2 (- high start))))))
      (while (< low high)
        (let ((middle (/ (+ low high 1) 2)))
          (if (fits middle)
              (setq low middle)
            (setq high (1- middle))))))
    low))

(cl-defun lcw-markdown-table-preview--wrap-cell (cell width unit)
  "Wrap CELL to WIDTH pixels, allowing UNIT pixels of padding on each side."
  (let ((limit (- width (* 2 unit))))
    (if (<= (lcw-markdown-table-preview--pixel-width cell) limit)
        (list cell)
      (let* ((offset 0)
             (offsets (vconcat '(0) (mapcar (lambda (glyph)
                                            (cl-incf offset (length glyph)))
                                          (string-glyph-split cell))))
             (last (1- (length offsets)))
             (start 0)
             lines)
        (while (< start last)
          (let* ((begin (aref offsets start))
                 (end (lcw-markdown-table-preview--fragment-end
                       cell offsets start limit)))
            (cond
             ((= end start)
              ;; Give a wide glyph some of the padding in a narrow column.
              (setq end (1+ start))
              (when (> (lcw-markdown-table-preview--pixel-width
                        (substring cell begin (aref offsets end)))
                       width)
                (cl-return-from lcw-markdown-table-preview--wrap-cell nil)))
             ((and (< end last)
                   (< (aref cell (aref offsets end)) 128)
                   (not (eq (aref cell (aref offsets end)) ?\s)))
              ;; Prefer word boundaries in Latin text.  Chinese and long
              ;; unbroken tokens can wrap at any glyph boundary.
              (setq end
                    (or (cl-loop for boundary from end downto (+ start 2)
                                 when (eq (aref cell
                                                (1- (aref offsets boundary)))
                                          ?\s)
                                 return boundary)
                        end))))
            (push (string-trim-right
                   (substring cell begin (aref offsets end)) " +")
                  lines)
            (setq start end)
            (while (and (< start last) (eq (aref cell (aref offsets start)) ?\s))
              (cl-incf start))))
        (nreverse lines)))))

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
         (available (- width content-width))
         (padding (min unit (/ available 2)))
         (space (- available (* 2 padding)))
         (left-extra (pcase alignment
                       ('right space)
                       ('center (/ space 2))
                       (_ 0)))
         (right-extra (- space left-extra)))
    (concat (lcw-markdown-table-preview--pixel-space (+ padding left-extra))
            cell
            (lcw-markdown-table-preview--pixel-space (+ padding right-extra)))))

(defun lcw-markdown-table-preview--row-lines (cells widths alignments unit border)
  "Wrap CELLS, pad them to WIDTHS with ALIGNMENTS, and join using BORDER."
  (let ((columns (cl-mapcar (lambda (cell width)
                             (lcw-markdown-table-preview--wrap-cell
                              cell width unit))
                           cells widths))
        lines)
    (when (cl-every #'consp columns)
      (while (cl-some #'consp columns)
        (push (concat (string-join
                       (cl-mapcar (lambda (column width alignment)
                                    (lcw-markdown-table-preview--pad-cell
                                     (or (car column) "") width alignment unit))
                                  columns widths alignments)
                       border)
                      border)
              lines)
        (setq columns (mapcar #'cdr columns)))
      (nreverse lines))))

(defun lcw-markdown-table-preview--rule (left middle right widths unit)
  "Build a table rule using LEFT, MIDDLE, RIGHT, WIDTHS, and pixel UNIT."
  (concat left
          (mapconcat (lambda (width) (make-string (/ width unit) ?─))
                     widths middle)
          right))

(defun lcw-markdown-table-preview--add-row (row leading tail &optional top bottom)
  "Show ROW with LEADING and TAIL text, plus optional TOP and BOTTOM rules."
  (let ((overlay (make-overlay (plist-get row :begin) (plist-get row :end)
                               nil t nil))
        (trailing (concat tail bottom)))
    ;; A nonempty replacement gives visual line motion a cursor position.
    ;; Pixel-width padding inside TAIL needs a separate overlay string.
    (overlay-put overlay 'display leading)
    (overlay-put overlay 'before-string top)
    (overlay-put overlay 'after-string trailing)
    (overlay-put overlay 'lcw-markdown-table-preview t)
    (overlay-put overlay 'lcw-markdown-table-preview-row (cons leading trailing))
    (overlay-put overlay 'lcw-markdown-table-preview-bottom bottom)
    (overlay-put overlay 'evaporate t)
    (push overlay lcw-markdown-table-preview--overlays)))

(defun lcw-markdown-table-preview--render (table window-width unit)
  "Render TABLE within WINDOW-WIDTH pixels using the character width UNIT."
  (let* ((rows (plist-get table :rows))
         (separator (plist-get table :separator))
         (separator-cells (plist-get table :separator-cells))
         (column-count (length separator-cells))
         (indent (plist-get table :indent))
         (column-budget
          (- window-width
             (lcw-markdown-table-preview--pixel-width indent)
             (* (1+ column-count) unit))))
    ;; Show source when the pane cannot fit the borders and minimum cells.
    (when (>= column-budget (* 3 column-count unit))
      (let* ((alignments (mapcar #'lcw-markdown-table-preview--alignment
                                 separator-cells))
             (raw-rows
              (cl-loop for row in rows
                       for first = t then nil
                       for face = (if first
                                      '(lcw-markdown-table-preview-header-face
                                        fixed-pitch)
                                    '(markdown-table-face fixed-pitch))
                       collect
                       (let ((cells (plist-get row :cells)))
                         ;; GFM pads short rows and ignores cells past the header.
                         (cl-loop repeat column-count
                                  collect (lcw-markdown-table-preview--inline
                                           (string-replace "\t" " " (or (pop cells) ""))
                                           face)))))
             (natural-widths
              (cl-loop for column below column-count
                       collect
                       (let ((content-width
                              (cl-loop for cells in raw-rows
                                       maximize
                                       (lcw-markdown-table-preview--pixel-width
                                        (nth column cells)))))
                         (* unit (+ 2 (ceiling content-width unit))))))
             (widths (lcw-markdown-table-preview--fit-widths
                      natural-widths column-budget unit))
             (border-face 'lcw-markdown-table-preview-border-face)
             (top (propertize
                   (concat indent (lcw-markdown-table-preview--rule
                                   "┌" "┬" "┐" widths unit) "\n")
                   'face border-face))
             (middle (lcw-markdown-table-preview--rule "├" "┼" "┤" widths unit))
             (bottom (propertize
                      (concat "\n" indent (lcw-markdown-table-preview--rule
                                           "└" "┴" "┘" widths unit))
                      'face border-face))
             (vertical (propertize "│" 'face border-face))
             (leading (concat indent vertical))
             (continuation (concat "\n" leading))
             (rendered-rows
              (mapcar (lambda (cells)
                        (lcw-markdown-table-preview--row-lines
                         cells widths alignments unit vertical))
                      raw-rows)))
        ;; A glyph wider than its entire column must stay visible as source.
        (when (cl-every #'consp rendered-rows)
          (cl-loop for row in rows
                   for lines in rendered-rows
                   for first = t then nil
                   do (lcw-markdown-table-preview--add-row
                       row leading (string-join lines continuation)
                       (when first top)
                       (when (= (plist-get row :end) (plist-get table :end))
                         bottom)))
          (lcw-markdown-table-preview--add-row
           separator
           (concat indent (propertize (substring middle 0 1) 'face border-face))
           (propertize (substring middle 1) 'face border-face)
           nil (when (null (cdr rows)) bottom)))))))

(defun lcw-markdown-table-preview--clear ()
  "Remove all table preview overlays from the current buffer."
  ;; Also remove tagged orphans.  Redisplay and window-change hooks can run
  ;; while a preview is being rebuilt; older versions could consequently lose
  ;; one overlay set from the tracking list and draw a table twice.
  (dolist (overlay (overlays-in (point-min) (point-max)))
    (when (overlay-get overlay 'lcw-markdown-table-preview)
      (delete-overlay overlay)))
  (mapc #'delete-overlay lcw-markdown-table-preview--overlays)
  (setq lcw-markdown-table-preview--overlays nil
        lcw-markdown-table-preview--active-row nil))

(defun lcw-markdown-table-preview--reveal-row ()
  "Show the source of the row at point and restore the previous row."
  (let ((row (unless buffer-read-only
               (cl-find-if
                (lambda (overlay)
                  (overlay-get overlay 'lcw-markdown-table-preview-row))
                (overlays-at (line-beginning-position)))))
        (previous lcw-markdown-table-preview--active-row))
    (unless (eq row previous)
      (when previous
        (let ((preview (overlay-get previous 'lcw-markdown-table-preview-row)))
          (overlay-put previous 'display (car preview))
          (overlay-put previous 'after-string (cdr preview))))
      (when row
        (overlay-put row 'display nil)
        (overlay-put row 'after-string
                     (overlay-get row 'lcw-markdown-table-preview-bottom)))
      (setq lcw-markdown-table-preview--active-row row))))

(defun lcw-markdown-table-preview-refresh (&optional force)
  "Refresh in-buffer Markdown table previews.
With FORCE, rebuild previews even if the text and window size are unchanged."
  (when (and lcw-markdown-table-preview-mode
             (not lcw-markdown-table-preview--refreshing))
    (let* ((lcw-markdown-table-preview--refreshing t)
           (tick (buffer-chars-modified-tick))
           (text-changed (/= tick lcw-markdown-table-preview--tick))
           (geometry (lcw-markdown-table-preview--measure)))
      (save-restriction
        (widen)
        (when (or force text-changed
                  (not (equal geometry lcw-markdown-table-preview--geometry)))
          (when text-changed
            (setq lcw-markdown-table-preview--tables
                  (lcw-markdown-table-preview--scan)))
          (lcw-markdown-table-preview--clear)
          (setq lcw-markdown-table-preview--geometry geometry
                lcw-markdown-table-preview--tick tick)
          (dolist (table lcw-markdown-table-preview--tables)
            (lcw-markdown-table-preview--render table (car geometry) (cdr geometry))))
        (lcw-markdown-table-preview--reveal-row)))))

(defun lcw-markdown-table-preview--before-redisplay (_window)
  "Refresh the preview when redisplay changes the available width."
  (lcw-markdown-table-preview-refresh))

(define-minor-mode lcw-markdown-table-preview-mode
  "Render GFM pipe tables in place while keeping their source editable."
  :lighter " Tbl"
  (if lcw-markdown-table-preview-mode
      (progn
        (add-hook 'post-command-hook
                  #'lcw-markdown-table-preview-refresh nil t)
        (add-hook 'pre-redisplay-functions
                  #'lcw-markdown-table-preview--before-redisplay nil t)
        (add-hook 'change-major-mode-hook #'lcw-markdown-table-preview--clear nil t)
        (lcw-markdown-table-preview-refresh t))
    (remove-hook 'post-command-hook
                 #'lcw-markdown-table-preview-refresh t)
    (remove-hook 'pre-redisplay-functions
                 #'lcw-markdown-table-preview--before-redisplay t)
    (remove-hook 'change-major-mode-hook #'lcw-markdown-table-preview--clear t)
    (lcw-markdown-table-preview--clear)
    (setq lcw-markdown-table-preview--tables nil
          lcw-markdown-table-preview--tick -1
          lcw-markdown-table-preview--geometry nil)))

(defun lcw-markdown-pretty ()
  "Use a more Obsidian-like Markdown display."
  (visual-line-mode 1)
  (lcw-markdown-enable-obsidian-highlights)
  (when (display-images-p)
    (markdown-display-inline-images)))

;; When updating vendor/markdown-mode, check the markdown-markup invisibility
;; category, display/composition properties, and markdown-inline-image-overlays.
;; Verify that moving onto and off a line still reveals and restores markup,
;; URLs, and images after font-lock runs.

(defvar markdown-inline-image-overlays)
(defvar-local lcw-markdown-reveal-line--range nil)
(defvar-local lcw-markdown-reveal-line--images nil)

(defun lcw-markdown-reveal-line--show-source (begin end)
  "Expose Markdown syntax between BEGIN and END while keeping syntax faces."
  (when (< begin end)
    (with-silent-modifications
      (remove-list-of-text-properties begin end '(display composition))
      (while (< begin end)
        (let ((next (next-single-property-change begin 'invisible nil end)))
          (when (eq (get-text-property begin 'invisible) 'markdown-markup)
            (remove-list-of-text-properties begin next '(invisible)))
          (setq begin next))))))

(defun lcw-markdown-reveal-line--after-fontify (&rest _)
  "Keep font-lock from concealing markup on the editing line."
  (when-let* ((range lcw-markdown-reveal-line--range)
              (begin (overlay-start range)))
    (lcw-markdown-reveal-line--show-source
     (max (point-min) begin)
     (min (point-max) (overlay-end range)))))

(defun lcw-markdown-reveal-line--restore-images ()
  "Restore image previews suppressed on the editing line."
  (dolist (entry lcw-markdown-reveal-line--images)
    (when (overlay-buffer (car entry))
      (overlay-put (car entry) 'display (cdr entry))))
  (setq lcw-markdown-reveal-line--images nil))

(defun lcw-markdown-reveal-line--refresh ()
  "Reveal the logical line at point and refontify the previous line."
  (save-restriction
    (widen)
    (let ((begin (line-beginning-position))
          (end (line-beginning-position 2))
          (range lcw-markdown-reveal-line--range))
      (unless (and range (eql begin (overlay-start range))
                   (= end (overlay-end range)))
        (when (and range (overlay-buffer range))
          (font-lock-flush (overlay-start range) (overlay-end range)))
        (if range
            (move-overlay range begin end)
          (setq lcw-markdown-reveal-line--range
                (make-overlay begin end nil nil t)))
        (lcw-markdown-reveal-line--show-source begin end)
        (lcw-markdown-reveal-line--restore-images))
      ;; Also catch image overlays created by a command on the same line.
      (when markdown-inline-image-overlays
        (dolist (overlay (overlays-in begin end))
          (when-let* ((image (overlay-get overlay 'display))
                      ((memq overlay markdown-inline-image-overlays)))
            (push (cons overlay image) lcw-markdown-reveal-line--images)
            (overlay-put overlay 'display nil)))))))

(defun lcw-markdown-reveal-line--disable ()
  "Remove the editing-line overrides and restore the usual preview."
  (remove-hook 'post-command-hook #'lcw-markdown-reveal-line--refresh t)
  (remove-hook 'change-major-mode-hook #'lcw-markdown-reveal-line--disable t)
  (remove-function (local 'font-lock-fontify-region-function)
                   #'lcw-markdown-reveal-line--after-fontify)
  (lcw-markdown-reveal-line--restore-images)
  (when-let* ((range lcw-markdown-reveal-line--range)
              (begin (overlay-start range)))
    (save-restriction
      (widen)
      (font-lock-flush begin (overlay-end range)))
    (delete-overlay range))
  (setq lcw-markdown-reveal-line--range nil))

(define-minor-mode lcw-markdown-reveal-line-mode
  "Show Markdown source on the editing line and preview elsewhere."
  :init-value nil
  (if lcw-markdown-reveal-line-mode
      (progn
        (add-function :after (local 'font-lock-fontify-region-function)
                      #'lcw-markdown-reveal-line--after-fontify)
        (add-hook 'post-command-hook #'lcw-markdown-reveal-line--refresh nil t)
        (add-hook 'change-major-mode-hook #'lcw-markdown-reveal-line--disable nil t)
        (lcw-markdown-reveal-line--refresh))
    (lcw-markdown-reveal-line--disable)))

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
  :hook ((markdown-mode . (lambda ()
                            (unless buffer-read-only
                              (lcw-markdown-reveal-line-mode 1))))
         (gfm-mode . lcw-markdown-limit-wiki-search)
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

(use-package typst-ts-mode
  :if (locate-library "typst-ts-mode")
  :mode "\\.typ\\'")

(defvar lcw-typst-markup-preview--query nil)
(defvar-local lcw-typst-markup-preview--line nil)

(defun lcw-typst-markup-preview--show-line (position source)
  "Show SOURCE or rendered markers on the line containing POSITION."
  (save-excursion
    (goto-char position)
    (dolist (overlay (overlays-in (line-beginning-position) (line-end-position)))
      (when-let* ((display (overlay-get overlay 'lcw-typst-markup-display)))
        (overlay-put overlay 'display (unless source display))))))

(defun lcw-typst-markup-preview--reveal-line ()
  (save-restriction
    (widen)
    (let* ((line (line-beginning-position))
           (marker lcw-typst-markup-preview--line)
           (previous (and marker (marker-position marker))))
      (unless (eql line previous)
        (when previous
          (lcw-typst-markup-preview--show-line previous nil))
        (if marker
            (set-marker marker line)
          (setq lcw-typst-markup-preview--line (copy-marker line)))
        (lcw-typst-markup-preview--show-line line t)))))

(defun lcw-typst-markup-preview--add-marker (kind node begin end editing-line)
  (let ((start (treesit-node-start node))
        (stop (treesit-node-end node)))
    (when (and (<= begin start) (< start stop) (<= stop end)
               (or (not (eq kind 'inline))
                   (not (treesit-node-check (treesit-node-parent node) 'has-error))))
      (goto-char start)
      (let ((editing (eql (line-beginning-position) editing-line))
            (display (if (eq kind 'bullet) "•" "")))
        (when (eq kind 'heading)
          (let* ((level (- stop start))
                 (typst-face (intern (format "typst-ts-markup-header-face-%d" level)))
                 (face (if (featurep 'markdown-mode)
                           (list :inherit (intern (format "markdown-header-face-%d" level))
                                 :height (face-attribute typst-face :height)
                                 :weight (face-attribute typst-face :weight nil t))
                         typst-face))
                 (overlay (make-overlay start (treesit-node-end (treesit-node-parent node)))))
            (overlay-put overlay 'lcw-typst-markup-preview t)
            (overlay-put overlay 'evaporate t)
            (overlay-put overlay 'face face))
          (goto-char stop)
          (skip-chars-forward " \t" (line-end-position))
          (setq stop (point)))
        (let ((overlay (make-overlay start stop)))
          (overlay-put overlay 'lcw-typst-markup-preview t)
          (overlay-put overlay 'evaporate t)
          (overlay-put overlay 'lcw-typst-markup-display display)
          (unless editing
            (overlay-put overlay 'display display)))))))

(defun lcw-typst-markup-preview--fontify (begin end)
  "Show Typst heading, list, and emphasis markup in the fontified region."
  (save-restriction
    (widen)
    (save-excursion
      (goto-char begin)
      (setq begin (line-beginning-position))
      (goto-char end)
      (unless (bolp)
        (setq end (line-beginning-position 2)))
      (dolist (overlay (overlays-in begin end))
        (when (overlay-get overlay 'lcw-typst-markup-preview)
          (delete-overlay overlay)))
      (when (< begin end)
        (let ((editing-line (marker-position lcw-typst-markup-preview--line))
              (query (or lcw-typst-markup-preview--query
                         (setq lcw-typst-markup-preview--query
                               (treesit-query-compile
                                'typst
                                '((heading ["=" "==" "===" "====" "=====" "======"] @heading)
                                  ((item "-" @bullet) (:equal "-" @bullet))
                                  (strong "*" @inline "*" @inline)
                                  (emph "_" @inline "_" @inline)))))))
          (dolist (capture (treesit-query-capture 'typst query begin end))
            (lcw-typst-markup-preview--add-marker
             (car capture) (cdr capture) begin end editing-line)))))))

(defun lcw-typst-markup-preview--disable ()
  (jit-lock-unregister #'lcw-typst-markup-preview--fontify)
  (remove-hook 'post-command-hook #'lcw-typst-markup-preview--reveal-line t)
  (remove-hook 'change-major-mode-hook #'lcw-typst-markup-preview--disable t)
  (save-restriction
    (widen)
    (remove-overlays (point-min) (point-max) 'lcw-typst-markup-preview t))
  (when lcw-typst-markup-preview--line
    (set-marker lcw-typst-markup-preview--line nil)
    (setq lcw-typst-markup-preview--line nil)))

(define-minor-mode lcw-typst-markup-preview-mode
  "Show rendered headings, bullet lists, and emphasis in Typst."
  :lighter nil
  (if (and lcw-typst-markup-preview-mode (derived-mode-p 'typst-ts-mode))
      (progn
        (require 'markdown-mode nil t)
        (lcw-typst-markup-preview--reveal-line)
        (add-hook 'post-command-hook #'lcw-typst-markup-preview--reveal-line nil t)
        (add-hook 'change-major-mode-hook #'lcw-typst-markup-preview--disable nil t)
        (jit-lock-register #'lcw-typst-markup-preview--fontify))
    (setq lcw-typst-markup-preview-mode nil)
    (lcw-typst-markup-preview--disable)))

(add-hook 'typst-ts-mode-hook #'lcw-typst-markup-preview-mode)

;; Typst's formula overlays and these block overlays share the source buffer.
(defvar lcw-typst-block-preview--process nil)
(defvar lcw-typst-block-preview-mode)
(defvar-local lcw-typst-block-preview--timer nil)
(defvar-local lcw-typst-block-preview--view nil)
(defvar-local lcw-typst-block-preview--overlays nil)
(defvar-local lcw-typst-block-preview--cache nil)
(defvar-local lcw-typst-block-preview--root nil)
(defvar-local lcw-typst-block-preview--editing nil)
(defvar lcw-typst-block-preview--block-query nil)
(defvar lcw-typst-block-preview--prelude-query nil)
(defvar lcw-typst-block-preview--path-query nil)

(defun lcw-typst-block-preview--source (node directory root)
  "Return NODE's source with literal import and image paths relative to ROOT."
  (let ((source (treesit-node-text node t)))
    (unless (equal directory root)
      (let ((start (treesit-node-start node))
            (paths (treesit-query-capture
                    node
                    (or lcw-typst-block-preview--path-query
                        (setq lcw-typst-block-preview--path-query
                              (treesit-query-compile
                               'typst
                               '((import import: (string) @path)
                                 ((call item: (ident) @image (group (string) @path))
                                  (:equal "image" @image)))))))))
        (dolist (capture (reverse paths))
          (when (eq (car capture) 'path)
            (let* ((path (cdr capture))
                   (text (treesit-node-text path t)))
              (when (string-match-p "\\`\"[^/@\"\\\\][^\"\\\\\n]*\"\\'" text)
                (let* ((name (substring text 1 -1))
                       (absolute (expand-file-name (concat "./" name) directory)))
                  (when (string-prefix-p root absolute)
                    (setq source
                          (concat (substring source 0 (- (treesit-node-start path) start))
                                  (json-serialize (concat "/" (substring absolute (length root))))
                                  (substring source (- (treesit-node-end path) start))))))))))))
    source))

(defun lcw-typst-block-preview--contains-point-p (overlay point)
  (<= (overlay-start overlay) point (overlay-end overlay)))

(defun lcw-typst-block-preview--display (overlay)
  (let ((display (unless (lcw-typst-block-preview--contains-point-p overlay (point))
                   (overlay-get overlay 'lcw-typst-image))))
    (unless (eq display (overlay-get overlay 'display))
      (overlay-put overlay 'display display))))

(defun lcw-typst-block-preview--small-png-p (data)
  "Check DATA's PNG dimensions before giving it to the display engine."
  (when (and (>= (length data) 24)
             (string-prefix-p "\211PNG\r\n\032\n" data)
             (equal (substring data 12 16) "IHDR"))
    (let ((size (bindat-unpack '((width u32) (height u32)) data 16)))
      (and (<= 1 (bindat-get-field size 'width) 1600)
           (<= 1 (bindat-get-field size 'height) 1600)))))

(defun lcw-typst-block-preview--make-image (png)
  (when (stringp png)
    (create-image png 'png t :max-width (nth 3 lcw-typst-block-preview--view)
                  :max-height 720)))

(defun lcw-typst-block-preview--forget-overlay (overlay)
  (when-let* ((image (overlay-get overlay 'lcw-typst-image)))
    (image-flush image))
  (delete-overlay overlay))

(defun lcw-typst-block-preview--filter (process output)
  ;; Stop reading after 1 MiB, even if the compiler keeps writing.
  (let ((size (+ (or (process-get process 'bytes) 0) (string-bytes output))))
    (if (> size (* 1024 1024))
        (progn
          (process-put process 'oversized t)
          (delete-process process))
      (process-put process 'bytes size)
      (process-put process 'chunks (cons output (process-get process 'chunks))))))

(defun lcw-typst-block-preview--finished (process _event)
  (when (memq (process-status process) '(exit signal failed))
    (when (eq lcw-typst-block-preview--process process)
      (setq lcw-typst-block-preview--process nil))
    (when-let* ((timer (process-get process 'timeout)))
      (cancel-timer timer))
    (when-let* ((input (process-get process 'input)))
      (ignore-errors (delete-file input)))
    (when-let* ((stderr (process-get process 'stderr))
                ((process-live-p stderr)))
      (delete-process stderr))
    (let* ((buffer (process-get process 'owner))
           (key (process-get process 'key))
           (png (and (not (process-get process 'oversized))
                     (zerop (process-exit-status process))
                     (apply #'concat (nreverse (process-get process 'chunks)))))
           (data (if (and png (lcw-typst-block-preview--small-png-p png)) png 'failed)))
      (when (and (buffer-live-p buffer) (not (process-get process 'cancelled)))
        (with-current-buffer buffer
          (when lcw-typst-block-preview-mode
            (setq lcw-typst-block-preview--cache
                  (seq-take (cons (cons key data) lcw-typst-block-preview--cache) 12))
            (dolist (overlay lcw-typst-block-preview--overlays)
              (when (and (equal key (car (overlay-get overlay 'lcw-typst-source)))
                         (= (buffer-chars-modified-tick) (overlay-get overlay 'lcw-typst-tick)))
                (overlay-put overlay 'lcw-typst-image (lcw-typst-block-preview--make-image data))
                (lcw-typst-block-preview--display overlay)))))))
    (lcw-typst-block-preview--next)))

(defun lcw-typst-block-preview--compile (source)
  (let ((default-directory lcw-typst-block-preview--root)
        (coding-system-for-write 'utf-8-unix)
        input stderr)
    (condition-case nil
        (progn
          (setq input (make-temp-file "emacs-typst-block-"))
          (write-region (cdr source) nil input nil 'silent)
          (setq stderr (make-pipe-process :name "typst-block-preview-stderr"
                                          :noquery t :filter #'ignore :sentinel #'ignore))
          (let* ((command (list (executable-find "typst") "compile" "--jobs" "1"
                                "--root" default-directory "--format" "png" "--ppi" "144" "-" "-"))
                 (prlimit (executable-find "prlimit"))
                 ;; Redirect stdin without blocking Emacs on process-send-string.
                 (process (make-process
                           :name "typst-block-preview" :connection-type 'pipe
                           :command (append (list "/bin/sh" "-c"
                                                  "exec < \"$1\"; rm -f -- \"$1\"; shift; exec \"$@\""
                                                  "typst-block-preview" input)
                                            (when prlimit
                                              (list prlimit "--as=536870912" "--"))
                                            command)
                           :coding 'binary :noquery t :stderr stderr
                           :filter #'lcw-typst-block-preview--filter
                           :sentinel #'lcw-typst-block-preview--finished)))
            (setq lcw-typst-block-preview--process process)
            (process-put process 'input input)
            (process-put process 'stderr stderr)
            (process-put process 'owner (current-buffer))
            (process-put process 'key (car source))
            (process-put process 'timeout (run-at-time 4 nil #'delete-process process))))
      (error
       (when input (ignore-errors (delete-file input)))
       (when stderr (delete-process stderr))
       (setq lcw-typst-block-preview--cache
             (seq-take (cons (cons (car source) 'failed) lcw-typst-block-preview--cache) 12))))))

(defun lcw-typst-block-preview--next ()
  ;; One additional compiler for all visible Typst buffers.
  (unless lcw-typst-block-preview--process
    (walk-windows
     (lambda (window)
       (with-current-buffer (window-buffer window)
         (when (and lcw-typst-block-preview-mode
                    (not lcw-typst-block-preview--process))
           (when-let* ((end (or (window-end window)
                                (when (eql (window-start window)
                                           (car lcw-typst-block-preview--view))
                                  (cadr lcw-typst-block-preview--view))))
                       (overlay
                        (seq-find
                         (lambda (entry)
                           (and (= (overlay-get entry 'lcw-typst-tick)
                                   (buffer-chars-modified-tick))
                                (overlay-buffer entry)
                                (< (window-start window) (overlay-end entry))
                                (< (overlay-start entry) end)
                                (not (lcw-typst-block-preview--contains-point-p
                                      entry (window-point window)))
                                (not (assoc (car (overlay-get entry 'lcw-typst-source))
                                            lcw-typst-block-preview--cache))))
                         lcw-typst-block-preview--overlays)))
             (lcw-typst-block-preview--compile (overlay-get overlay 'lcw-typst-source))))))
     'no-minibuf 'visible)))

(defun lcw-typst-block-preview--refresh (buffer)
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq lcw-typst-block-preview--timer nil)
      (when-let* ((lcw-typst-block-preview-mode)
                  (window (get-buffer-window buffer 'visible))
                  (beg (window-start window))
                  (end (window-end window t))
                  ((< beg end)))
        (let* ((tick (buffer-chars-modified-tick))
               (view (list beg end tick (max 1 (min 720 (window-body-width window t))))))
          (unless (equal view lcw-typst-block-preview--view)
            (setq lcw-typst-block-preview--view view)
            (save-restriction
              (widen)
              (let* ((blocks
                      (treesit-query-capture
                       'typst
                       (or lcw-typst-block-preview--block-query
                           (setq lcw-typst-block-preview--block-query
                                 (treesit-query-compile
                                  'typst
                                  '(((code (call item: (ident) @name)) @block
                                     (:match "\\`\\(table\\|image\\|figure\\)\\'" @name))))))
                       beg end))
                     (directory (file-name-directory (or buffer-file-name default-directory)))
                     (root (when blocks
                             (or lcw-typst-block-preview--root
                                 (setq lcw-typst-block-preview--root
                                       (if-let* ((project (project-current nil directory)))
                                           (file-name-as-directory (project-root project))
                                         directory)))))
                     (prelude
                      (when blocks
                        (treesit-query-capture
                         'typst
                         (or lcw-typst-block-preview--prelude-query
                             (setq lcw-typst-block-preview--prelude-query
                                   (treesit-query-compile 'typst '((code [(let) (import)]) @def))))
                         (point-min) (min end (+ (point-min) 65536)) t)))
                     (old lcw-typst-block-preview--overlays)
                     (last-end 0)
                     previews)
                (dolist (capture blocks)
                  (when (and (eq (car capture) 'block) (< (length previews) 8))
                    (let* ((node (cdr capture))
                           (start (treesit-node-start node))
                           (stop (treesit-node-end node)))
                      (when (and (>= start last-end)
                                 (<= (- stop start) 16384)
                                 (not (treesit-node-check node 'has-error))
                                 (not (treesit-parent-until node "code")))
                        (let ((source
                               (concat
                                (mapconcat
                                 (lambda (definition)
                                   (if (and (<= (treesit-node-end definition) start)
                                            (<= (- (treesit-node-end definition)
                                                   (treesit-node-start definition)) 4096)
                                            (not (treesit-parent-until definition "code")))
                                       (lcw-typst-block-preview--source definition directory root)
                                     ""))
                                 prelude "\n")
                                "\n#set page(width: 400pt, height: auto, margin: 5pt)\n"
                                (lcw-typst-block-preview--source node directory root))))
                          (when (<= (string-bytes source) 24576)
                            (let* ((key (secure-hash 'sha256 source))
                                   (existing (seq-find
                                              (lambda (overlay)
                                                (and (eql start (overlay-start overlay))
                                                     (eql stop (overlay-end overlay))
                                                     (equal key (car (overlay-get overlay 'lcw-typst-source)))
                                                     (= (nth 3 view) (overlay-get overlay 'lcw-typst-width))))
                                              old))
                                   (overlay (or existing (make-overlay start stop nil t nil))))
                              (unless existing
                                (overlay-put overlay 'priority 1)
                                (overlay-put overlay 'evaporate t)
                                (overlay-put overlay 'lcw-typst-width (nth 3 view))
                                (overlay-put overlay 'lcw-typst-source (cons key source))
                                (overlay-put overlay 'lcw-typst-image
                                             (lcw-typst-block-preview--make-image
                                              (cdr (assoc key lcw-typst-block-preview--cache)))))
                              (overlay-put overlay 'lcw-typst-tick tick)
                              (push overlay previews)
                              (setq old (delq overlay old) last-end stop))))))))
                (mapc #'lcw-typst-block-preview--forget-overlay old)
                (setq lcw-typst-block-preview--overlays (nreverse previews))
                (lcw-typst-block-preview--reveal))))
          (lcw-typst-block-preview--next))))))

(defun lcw-typst-block-preview--schedule (&rest _args)
  (unless lcw-typst-block-preview--timer
    (setq lcw-typst-block-preview--timer
          (run-at-time 0.35 nil #'lcw-typst-block-preview--refresh (current-buffer)))))

(defun lcw-typst-block-preview--changed (&rest _args)
  (when lcw-typst-block-preview--timer
    (cancel-timer lcw-typst-block-preview--timer)
    (setq lcw-typst-block-preview--timer nil))
  (lcw-typst-block-preview--schedule))

(defun lcw-typst-block-preview--reveal ()
  (let (editing)
    (dolist (overlay lcw-typst-block-preview--overlays)
      (when (overlay-buffer overlay)
        (lcw-typst-block-preview--display overlay)
        (when (lcw-typst-block-preview--contains-point-p overlay (point))
          (setq editing overlay))))
    (unless (eq editing lcw-typst-block-preview--editing)
      (setq lcw-typst-block-preview--editing editing)
      (lcw-typst-block-preview--next))))

(defun lcw-typst-block-preview--clear ()
  (when lcw-typst-block-preview--timer
    (cancel-timer lcw-typst-block-preview--timer))
  (mapc #'lcw-typst-block-preview--forget-overlay lcw-typst-block-preview--overlays)
  (setq lcw-typst-block-preview--timer nil
        lcw-typst-block-preview--overlays nil
        lcw-typst-block-preview--view nil
        lcw-typst-block-preview--cache nil
        lcw-typst-block-preview--root nil
        lcw-typst-block-preview--editing nil)
  (when (and lcw-typst-block-preview--process
             (eq (process-get lcw-typst-block-preview--process 'owner) (current-buffer)))
    (process-put lcw-typst-block-preview--process 'cancelled t)
    (delete-process lcw-typst-block-preview--process)))

(defun lcw-typst-block-preview-refresh ()
  "Rebuild Typst block previews, including files changed outside this buffer."
  (interactive)
  (when lcw-typst-block-preview-mode
    (lcw-typst-block-preview--clear)
    (lcw-typst-block-preview--schedule)))

(define-minor-mode lcw-typst-block-preview-mode
  "Preview visible Typst table, image, and figure calls in the source buffer."
  :lighter nil
  (let ((hooks '((after-change-functions . lcw-typst-block-preview--changed)
                 (window-scroll-functions . lcw-typst-block-preview--schedule)
                 (window-size-change-functions . lcw-typst-block-preview--schedule)
                 (post-command-hook . lcw-typst-block-preview--reveal)
                 (change-major-mode-hook . lcw-typst-block-preview--clear)
                 (kill-buffer-hook . lcw-typst-block-preview--clear))))
    (if lcw-typst-block-preview-mode
        (if (and (derived-mode-p 'typst-ts-mode)
                 (display-images-p) (image-type-available-p 'png)
                 (executable-find "typst") (not (file-remote-p default-directory)))
            (progn
              (dolist (hook hooks)
                (add-hook (car hook) (cdr hook) nil t))
              (lcw-typst-block-preview--schedule))
          (setq lcw-typst-block-preview-mode nil))
      (dolist (hook hooks)
        (remove-hook (car hook) (cdr hook) t))
      (lcw-typst-block-preview--clear))))

(add-hook 'typst-ts-mode-hook #'lcw-typst-block-preview-mode)

(use-package typst-overlay
  :if (locate-library "typst-overlay")
  :commands typst-overlay-mode
  :hook (typst-ts-mode . (lambda ()
                           (when (and (display-images-p)
                                      (image-type-available-p 'svg)
                                      (executable-find "typst"))
                             (typst-overlay-mode 1))))
  :custom
  (typst-overlay-preview nil)
  (typst-overlay-max-active-compiles 2))

;; PDF Tools loads when a PDF is opened and never invokes a system package manager.
(use-package pdf-tools
  :if (locate-library "pdf-tools")
  :defer t
  :init
  (setq pdf-view-display-size 'fit-width)
  (pdf-loader-install nil t)
  :hook (pdf-view-mode . (lambda () (display-line-numbers-mode -1))))

(provide (quote init-docs))
;;; init-docs.el ends here
