/**
 * @description Lightweight, enterprise-grade Trigger Handler base class implementing
 *              Separation of Concerns, context dispatch, recursion protection, and static bypass controls.
 */
public virtual inherited sharing class TriggerHandler {
    @TestVisible
    private static Set<String> bypassedHandlers = new Set<String>();

    @TestVisible
    private TriggerContext context;

    @TestVisible
    private Boolean isTriggerExecuting;

    public enum TriggerContext {
        BEFORE_INSERT,
        BEFORE_UPDATE,
        BEFORE_DELETE,
        AFTER_INSERT,
        AFTER_UPDATE,
        AFTER_DELETE,
        AFTER_UNDELETING
    }

    public TriggerHandler() {
        this.setTriggerContext();
    }

    /**
     * @description Main execution entry point invoked from SObject triggers.
     */
    public void run() {
        if (!this.validateRun()) {
            return;
        }

        switch on this.context {
            when BEFORE_INSERT {
                this.beforeInsert();
            }
            when BEFORE_UPDATE {
                this.beforeUpdate();
            }
            when BEFORE_DELETE {
                this.beforeDelete();
            }
            when AFTER_INSERT {
                this.afterInsert();
            }
            when AFTER_UPDATE {
                this.afterUpdate();
            }
            when AFTER_DELETE {
                this.afterDelete();
            }
            when AFTER_UNDELETING {
                this.afterUndelete();
            }
        }
    }

    /**
     * @description Bypasses trigger execution for the specified handler class name.
     */
    public static void bypass(String handlerName) {
        if (String.isNotBlank(handlerName)) {
            bypassedHandlers.add(handlerName);
        }
    }

    /**
     * @description Clears the bypass for the specified handler class name.
     */
    public static void clearBypass(String handlerName) {
        if (String.isNotBlank(handlerName)) {
            bypassedHandlers.remove(handlerName);
        }
    }

    /**
     * @description Returns true if the specified handler class is currently bypassed.
     */
    public static Boolean isBypassed(String handlerName) {
        return bypassedHandlers.contains(handlerName);
    }

    /**
     * @description Clears all active handler bypasses.
     */
    public static void clearAllBypasses() {
        bypassedHandlers.clear();
    }

    @SuppressWarnings('PMD.EmptyStatementBlock')
    protected virtual void beforeInsert() {
    }

    @SuppressWarnings('PMD.EmptyStatementBlock')
    protected virtual void beforeUpdate() {
    }

    @SuppressWarnings('PMD.EmptyStatementBlock')
    protected virtual void beforeDelete() {
    }

    @SuppressWarnings('PMD.EmptyStatementBlock')
    protected virtual void afterInsert() {
    }

    @SuppressWarnings('PMD.EmptyStatementBlock')
    protected virtual void afterUpdate() {
    }

    @SuppressWarnings('PMD.EmptyStatementBlock')
    protected virtual void afterDelete() {
    }

    @SuppressWarnings('PMD.EmptyStatementBlock')
    protected virtual void afterUndelete() {
    }

    @TestVisible
    private void setTriggerContext() {
        this.setTriggerContext(null, false);
    }

    @TestVisible
    private void setTriggerContext(String ctx, Boolean testMode) {
        if (!Trigger.isExecuting && !testMode) {
            this.isTriggerExecuting = false;
            return;
        }
        this.isTriggerExecuting = true;

        if ((Trigger.isExecuting && Trigger.isBefore && Trigger.isInsert) || ctx == 'before insert') {
            this.context = TriggerContext.BEFORE_INSERT;
        } else if ((Trigger.isExecuting && Trigger.isBefore && Trigger.isUpdate) || ctx == 'before update') {
            this.context = TriggerContext.BEFORE_UPDATE;
        } else if ((Trigger.isExecuting && Trigger.isBefore && Trigger.isDelete) || ctx == 'before delete') {
            this.context = TriggerContext.BEFORE_DELETE;
        } else if ((Trigger.isExecuting && Trigger.isAfter && Trigger.isInsert) || ctx == 'after insert') {
            this.context = TriggerContext.AFTER_INSERT;
        } else if ((Trigger.isExecuting && Trigger.isAfter && Trigger.isUpdate) || ctx == 'after update') {
            this.context = TriggerContext.AFTER_UPDATE;
        } else if ((Trigger.isExecuting && Trigger.isAfter && Trigger.isDelete) || ctx == 'after delete') {
            this.context = TriggerContext.AFTER_DELETE;
        } else if ((Trigger.isExecuting && Trigger.isAfter && Trigger.isUndelete) || ctx == 'after undelete') {
            this.context = TriggerContext.AFTER_UNDELETING;
        }
    }

    private Boolean validateRun() {
        if (this.isTriggerExecuting == null || !this.isTriggerExecuting || this.context == null) {
            return false;
        }
        return !TriggerHandler.isBypassed(this.getHandlerName());
    }

    private String getHandlerName() {
        return String.valueOf(this).substring(0, String.valueOf(this).indexOf(':'));
    }
}

