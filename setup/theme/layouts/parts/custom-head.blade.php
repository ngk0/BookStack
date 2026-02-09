{{--
LAPORTE Theme Override: Custom Head Content

This overrides the default BookStack template to REMOVE the exclusion
of custom head content from settings/admin pages.

Original excludes: request()->routeIs('settings.category')
This override: Allows custom head on ALL pages including settings
--}}
@inject('headContent', 'BookStack\Theming\CustomHtmlHeadContentProvider')

@if(setting('app-custom-head'))
    @php
        // Used by the LAPORTE admin banner JS to authenticate to the Content Generator proxy.
        // Keep this token out of the DB-stored head HTML and only expose it to admin users.
        $cgBannerToken = env('CG_BANNER_TOKEN');
    @endphp

    @if(!user()->isGuest() && userCan(\BookStack\Permissions\Permission::SettingsManage))
        <meta name="cg-admin" content="1">
        @if($cgBannerToken)
            <meta name="cg-token" content="{{ $cgBannerToken }}">
        @endif
    @endif

    {!! $headContent->forWeb() !!}
@endif
