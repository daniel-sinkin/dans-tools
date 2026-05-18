#include "clang-tidy/ClangTidyCheck.h"
#include "clang-tidy/ClangTidyModule.h"

#include "clang/AST/ASTContext.h"
#include "clang/AST/Attr.h"
#include "clang/AST/Decl.h"
#include "clang/AST/Expr.h"
#include "clang/AST/ExprCXX.h"
#include "clang/AST/Type.h"
#include "clang/AST/TypeLoc.h"
#include "clang/ASTMatchers/ASTMatchFinder.h"
#include "clang/Basic/SourceManager.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Registry.h"

namespace clang::tidy::ds_dev {
namespace {
[[nodiscard]] auto has_annotation(const Decl &decl, llvm::StringRef name) -> bool {
    for (const auto *attr : decl.specific_attrs<AnnotateAttr>()) {
        if (attr->getAnnotation() == name)
            return true;
    }
    return false;
}

[[nodiscard]] auto is_user_source(const SourceManager &source_manager, SourceLocation location)
    -> bool {
    if (location.isInvalid())
        return false;
    const auto expansion_location = source_manager.getExpansionLoc(location);
    return not source_manager.isInSystemHeader(expansion_location);
}

[[nodiscard]] auto is_const_binding(QualType type) -> bool {
    if (type->isReferenceType())
        return type->getPointeeType().isConstQualified();
    return type.isConstQualified();
}

[[nodiscard]] auto is_mutable_borrow(QualType type) -> bool {
    if (type->isReferenceType())
        return not type->getPointeeType().isConstQualified();

    if (type->isPointerType()) {
        return not type->getPointeeType().isConstQualified();
    }

    return false;
}

[[nodiscard]] auto is_by_value(QualType type) -> bool {
    return not type->isReferenceType();
}

[[nodiscard]] auto is_cheap_copy(QualType type, ASTContext &context) -> bool {
    const auto unqualified_type = type.getNonReferenceType().getUnqualifiedType();
    if (unqualified_type->isDependentType())
        return true;
    if (unqualified_type->isIncompleteType())
        return true;
    if (!unqualified_type.isTriviallyCopyableType(context))
        return false;

    const auto type_size = context.getTypeSizeInChars(unqualified_type);
    const auto pointer_size = context.getTypeSizeInChars(context.VoidPtrTy);
    return type_size.getQuantity() <= (pointer_size.getQuantity() * 2);
}

[[nodiscard]] auto was_written_with_auto(const VarDecl &decl) -> bool {
    const auto *type_source_info = decl.getTypeSourceInfo();
    if (type_source_info == nullptr)
        return false;
    return not type_source_info->getTypeLoc().getContainedAutoTypeLoc().isNull();
}

[[nodiscard]] auto expression_originates_from_lvalue(const Expr *expr) -> bool {
    if (expr == nullptr)
        return false;

    const auto *ignored_expr = expr->IgnoreParenImpCasts();
    if (ignored_expr->isLValue())
        return true;

    if (const auto *temporary = dyn_cast<CXXBindTemporaryExpr>(ignored_expr)) {
        return expression_originates_from_lvalue(temporary->getSubExpr());
    }

    if (const auto *materialized = dyn_cast<MaterializeTemporaryExpr>(ignored_expr)) {
        return expression_originates_from_lvalue(materialized->getSubExpr());
    }

    if (const auto *construct = dyn_cast<CXXConstructExpr>(ignored_expr)) {
        if (construct->getNumArgs() != 1)
            return false;
        return expression_originates_from_lvalue(construct->getArg(0));
    }

    return false;
}

[[nodiscard]] auto initializes_from_lvalue(const VarDecl &decl) -> bool {
    return expression_originates_from_lvalue(decl.getInit());
}

class DevelopmentMarkersCheck final : public ClangTidyCheck {
public:
    DevelopmentMarkersCheck(llvm::StringRef name, ClangTidyContext *context)
        : ClangTidyCheck{name, context} {
    }

    void registerMatchers(ast_matchers::MatchFinder *finder) override {
        using namespace ast_matchers;
        finder->addMatcher(varDecl(unless(parmVarDecl())).bind("var"), this);
        finder->addMatcher(parmVarDecl().bind("param"), this);
    }

    void check(const ast_matchers::MatchFinder::MatchResult &result) override {
        if (const auto *param = result.Nodes.getNodeAs<ParmVarDecl>("param")) {
            check_param(*param, *result.SourceManager, *result.Context);
            return;
        }

        if (const auto *var = result.Nodes.getNodeAs<VarDecl>("var")) {
            check_var(*var, *result.SourceManager, *result.Context);
        }
    }

private:
    void check_var(const VarDecl &var, const SourceManager &source_manager, ASTContext &context) {
        if (not is_user_source(source_manager, var.getLocation()))
            return;
        if (not var.isLocalVarDecl())
            return;
        if (var.isImplicit())
            return;
        if (var.isExceptionVariable())
            return;
        if (var.isInitCapture())
            return;
        const auto *function = dyn_cast_or_null<FunctionDecl>(var.getDeclContext());
        if ((function != nullptr) and (function->isImplicit() or function->isDefaulted()))
            return;

        const auto has_mut = has_annotation(var, "mut");
        const auto has_cpy = has_annotation(var, "cpy");
        const auto is_const = is_const_binding(var.getType());

        if (has_mut and is_const) {
            diag(var.getLocation(), "mutable marker on const local variable is contradictory");
        }

        if (has_cpy) {
            diag(
                var.getLocation(),
                "use copy(...) for local explicit copies; reserve cpy for declarations that "
                "receive a by-value copy");
        }

        if ((not is_const) and (not has_mut)) {
            diag(var.getLocation(), "local variable must be const or mut");
        }

        if (was_written_with_auto(var) and is_by_value(var.getType()) and (not is_cheap_copy(var.getType(), context)) and initializes_from_lvalue(var)) {
            diag(
                var.getLocation(),
                "by-value auto initialized from a non-cheap lvalue must use copy(...) or bind by "
                "reference");
        }
    }

    void check_param(
        const ParmVarDecl &param, const SourceManager &source_manager, ASTContext &context) {
        if (not is_user_source(source_manager, param.getLocation()))
            return;
        if (param.isImplicit())
            return;
        const auto *function = dyn_cast_or_null<FunctionDecl>(param.getDeclContext());
        if ((function != nullptr) and (function->isImplicit() or function->isDefaulted()))
            return;

        const auto has_mut = has_annotation(param, "mut");
        const auto has_cpy = has_annotation(param, "cpy");
        const auto type = param.getType();

        if (has_mut and not is_mutable_borrow(type)) {
            diag(
                param.getLocation(),
                "mut parameter marker is only valid for mutable references or mutable pointers");
        }

        if (has_cpy and not is_by_value(type)) {
            diag(param.getLocation(), "cpy parameter marker is only valid for by-value parameters");
        }

        if (is_mutable_borrow(type) and not has_mut) {
            diag(param.getLocation(), "mutable reference or pointer parameter must be marked mut");
        }

        if (is_by_value(type) and (not is_cheap_copy(type, context)) and not has_cpy) {
            diag(param.getLocation(), "non-cheap by-value parameter must be marked cpy");
        }
    }
};

class DsDevMarkerTidyModule final : public ClangTidyModule {
public:
    void addCheckFactories(ClangTidyCheckFactories &factories) override {
        factories.registerCheck<DevelopmentMarkersCheck>("ds-dev-marker-tidy");
    }
};

static ClangTidyModuleRegistry::Add<DsDevMarkerTidyModule> module{
    "ds-dev-module",
    "Adds ds-dev project development checks.",
};
} // namespace
} // namespace clang::tidy::ds_dev

extern "C" int ds_dev_marker_tidy_plugin_anchor = 0;
