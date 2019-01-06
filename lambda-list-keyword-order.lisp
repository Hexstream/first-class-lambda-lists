(in-package #:first-class-lambda-lists)

(eval-when t

  (defclass lambda-list-keyword-order-definitions (defsys:standard-system)
    ())

  (defvar *lambda-list-keyword-order-definitions*
    (make-instance 'lambda-list-keyword-order-definitions :name 'fcll:lambda-list-keyword-order))

  (setf (defsys:locate (defsys:root-system) 'fcll:lambda-list-keyword-order)
        *lambda-list-keyword-order-definitions*)

  (defun %ensure-lambda-list-keyword-order (name specification)
    (%ensure-definition *lambda-list-keyword-order-definitions* name
                        'fcll:standard-lambda-list-keyword-order
                        :specification specification))

  (defmethod defsys:expand-definition ((system lambda-list-keyword-order-definitions) name environment args &key)
    (destructuring-bind (specification) args
      `(%ensure-lambda-list-keyword-order ',name ',specification))))


(defclass fcll:lambda-list-keyword-order () ())

(defclass fcll:standard-lambda-list-keyword-order (fcll:lambda-list-keyword-order defsys:name-mixin)
  ((%specification :initarg :specification
                   :reader specification
                   :type cons)
   (%tree :reader tree)))

(defun %transform-keyword-order (keyword-order process-atom)
  (labels ((recurse (spec)
             (etypecase spec
               (cons (destructuring-bind (operator &rest args) spec
                       (check-type operator (member list or))
                       (let ((args (mapcan (let ((to-splice `(cons (cons (eql ,operator) list)
                                                                   null)))
                                             (lambda (arg)
                                               (let ((result (recurse arg)))
                                                 (if (typep result to-splice)
                                                     (rest (first result))
                                                     result))))
                                           args)))
                         (case (length args)
                           (0 nil)
                           (1 args)
                           (t (list (cons operator args)))))))
               (atom (funcall process-atom spec)))))
    (first (recurse keyword-order))))

(defun %lambda-list-keyword-order-specification-to-tree (specification)
  (%transform-keyword-order specification (lambda (spec)
                                            (check-type spec symbol)
                                            (list (defsys:locate *lambda-list-keyword-definitions* spec)))))

(defmethod shared-initialize :after ((instance fcll:standard-lambda-list-keyword-order) slot-names &key)
  (setf (slot-value instance '%tree)
        (%lambda-list-keyword-order-specification-to-tree (specification instance))))

(define (fcll:lambda-list-keyword-order :standard)
  (list &whole
        (or (list (or :required :required-specializable)
                  (or &optional :&optional-no-defaulting)
                  (or &rest &body)
                  (or &key :&key-no-defaulting)
                  &aux
                  :&environment-last)
            :&environment-not-before-&whole)))
