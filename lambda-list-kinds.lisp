(in-package #:first-class-lambda-lists)

(defclass fcll:lambda-list-kind () ())

(defmethod defsys:locate ((system lambda-list-kind-definitions) (name fcll:lambda-list-kind) &rest keys)
  (declare (ignore keys))
  name)

(defclass fcll:standard-lambda-list-kind (fcll:lambda-list-kind defsys:name-mixin)
  ((%operator :initarg :operator
              :reader operator)
   (%keywords :initarg :keywords
              :reader keywords
              :type list)
   (%keyword-order :reader keyword-order)
   (%recurse :initarg :recurse
             :reader recurse
             :type (or null fcll:lambda-list-kind)
             :initform nil)
   (%default-initform :initarg :default-initform
                      :reader default-initform
                      :initform nil)
   (%parser :reader parser)))

(defun %compute-keyword-order (keywords keyword-order)
  (%transform-keyword-order keyword-order
                            (lambda (keyword)
                              (when (member (defsys:name keyword) keywords
                                            :key #'defsys:name :test #'eq)
                                (list keyword)))))

(defun %make-list-processor-maker (recurse args)
  (let ((arg-processor-makers (mapcar recurse args)))
    (lambda ()
      (let ((arg-processors (mapcar #'funcall arg-processor-makers)))
        (lambda (tail)
          (if tail
              (let ((all-sections nil))
                (block nil
                  (mapl (lambda (processors)
                          (multiple-value-bind (new-tail sections)
                              (funcall (first processors) tail)
                            (push sections all-sections)
                            (unless new-tail
                              (setf tail new-tail)
                              (return))
                            (unless (eq new-tail tail)
                              (setf arg-processors (rest processors)
                                    tail new-tail))))
                        arg-processors))
                (values tail
                        (apply #'nconc (nreverse all-sections))
                        (not arg-processors)))
              (values tail nil (not arg-processors))))))))

(defun %make-or-processor-dispenser (list)
  (let* ((elements (copy-list list))
         (previous-cons (last elements))
         (elements-count (length elements))
         (unproductive-streak 0))
    (nconc elements elements)
    (lambda (tail)
      (block nil
        (multiple-value-bind (new-tail sections donep)
            (funcall (first elements) tail)
          (let ((next (cdr elements)))
            (when donep
              (when (eq next elements)
                (return (values new-tail sections t)))
              (setf (rest previous-cons) next
                    unproductive-streak 0)
              (decf elements-count))
            (shiftf previous-cons elements next)
            (when (eq new-tail tail)
              (incf unproductive-streak)
              (when (= unproductive-streak elements-count)
                (return (values new-tail sections :stuck))))
            (values new-tail sections nil)))))))

(defun %make-or-processor-maker (recurse args)
  (let ((arg-processor-makers (mapcar (lambda (arg)
                                        (funcall recurse arg t))
                                      args)))
    (lambda ()
      (let ((arg-processor-dispenser (%make-or-processor-dispenser
                                      (mapcar #'funcall arg-processor-makers))))
        (lambda (tail)
          (if tail
              (let* ((all-sections nil)
                     (donep (block nil
                              (loop
                                 (multiple-value-bind (new-tail sections donep)
                                     (funcall arg-processor-dispenser tail)
                                   (push sections all-sections)
                                   (setf tail new-tail)
                                   (when (or donep (not tail))
                                     (return donep)))))))
                (values tail
                        (apply #'nconc (nreverse all-sections))
                        (not (eq donep :stuck))))
              (values tail nil t)))))))

;;; ↑ WORST. CODE. EVER! ↓

(defun %make-parser (keyword-order recursive-lambda-list-kind)
  (labels ((recurse (spec &optional backtrackp)
             (etypecase spec
               (cons (destructuring-bind (operator &rest args) spec
                       (check-type args cons)
                       (ecase operator
                         (list (%make-list-processor-maker #'recurse args))
                         (or (%make-or-processor-maker #'recurse args)))))
               (fcll:lambda-list-keyword
                (let ((parser (parser spec)))
                  (if backtrackp
                      (lambda ()
                        (lambda (tail)
                          (multiple-value-bind (new-tail sections) (funcall parser tail)
                            (values new-tail sections (not (eq new-tail tail))))))
                      (lambda ()
                        parser)))))))
    (let ((parser-maker (recurse keyword-order)))
      (lambda (tail)
        (multiple-value-bind (new-tail sections donep)
            (let ((parser (funcall parser-maker)))
              (if recursive-lambda-list-kind
                  (let ((*parse-recursable-variable*
                         (lambda (variable)
                           (make-instance 'standard-lambda-list
                                          :kind recursive-lambda-list-kind
                                          :parse variable))))
                    (funcall parser tail))
                  (funcall parser tail)))
          (if new-tail
              (error "Could not completely parse lambda list:~@
                      ~S~%new-tail: ~S~%donep: ~S~%sections: ~S"
                     tail new-tail donep sections)
              sections))))))

(defmethod shared-initialize :after ((kind fcll:standard-lambda-list-kind) slot-names &key)
  (let* ((keywords (mapcar (%make-keyword-canonicalizer) (slot-value kind '%keywords)))
         (keyword-order (%compute-keyword-order
                         keywords
                         (tree (defsys:locate 'fcll:lambda-list-keyword-order :standard))))
         (recursive-lambda-list-kind
          (let ((recurse-kind (slot-value kind '%recurse)))
            (when recurse-kind
              (if (eq recurse-kind t)
                  kind
                  (defsys:locate *lambda-list-kind-definitions* recurse-kind))))))
    (setf (slot-value kind '%keywords)
          keywords
          (slot-value kind '%keyword-order)
          keyword-order
          (slot-value kind '%recurse)
          recursive-lambda-list-kind
          (slot-value kind '%parser)
          (%make-parser keyword-order recursive-lambda-list-kind))))

(defun %derive-keywords-list (&key (from :ordinary) add remove replace)
  (let ((canonicalize (%make-keyword-canonicalizer)))
    (flet ((listify (object)
             (if (listp object)
                 object
                 (list object))))
      (multiple-value-bind (replace-add replace-remove)
          (let ((add nil)
                (remove nil))
            (dolist (cons replace)
              (push (funcall canonicalize (first cons)) remove)
              (push (funcall canonicalize (second cons)) add))
            (values (nreverse add) (nreverse remove)))
        (let ((inherited (keywords (defsys:locate *lambda-list-kind-definitions* from)))
              (add (nconc (mapcar canonicalize (listify add)) replace-add))
              (remove (nconc (mapcar canonicalize (listify remove)) replace-remove)))
          (let ((shared (intersection add remove :test #'%keyword=)))
            (when shared
              (error "Cannot both add and remove the same lambda list keywords: ~S" shared)))
          (let ((overadd (intersection inherited add :test #'%keyword=)))
            (when overadd
              (warn "Tried to add already inherited lambda list keywords: ~S" overadd)))
          (let ((overremove (set-difference remove inherited :test #'%keyword=)))
            (when overremove
              (warn "Tried to remove already not inherited lambda list keywords: ~S" overremove)))
          (union (set-difference inherited remove :test #'%keyword=) add :test #'%keyword=))))))

(define (fcll:lambda-list-kind :ordinary) defun
  (:required &optional &rest &key &aux)) ;&allow-other-keys is subordinate to &key, so implied by it.

(define (fcll:lambda-list-kind :generic-function) defgeneric
  (:derive :replace ((&optional :&optional-no-defaulting)
                     (&key :&key-no-defaulting))
           :remove &aux))

(define (fcll:lambda-list-kind :specialized) defmethod
  (:derive :replace ((:required :required-specializable))))

(define (fcll:lambda-list-kind :destructuring) destructuring-bind
  (:derive :add (&whole &body))
  :recurse t)

(define (fcll:lambda-list-kind :macro) defmacro
  (:derive :from :destructuring :add :&environment-not-before-&whole)
  :recurse :destructuring)

(define (fcll:lambda-list-kind :boa) defstruct
  (:derive))

(define (fcll:lambda-list-kind :defsetf) defsetf
  (:derive :add :&environment-last :remove &aux))

(define (fcll:lambda-list-kind :deftype) deftype
  (:derive :from :macro)
  :recurse :destructuring
  :default-initform ''*)

(define (fcll:lambda-list-kind :define-modify-macro) define-modify-macro
  (:derive :remove (&key &aux)))

(define (fcll:lambda-list-kind :define-method-combination-arguments) define-method-combination
  (:derive :add &whole))
