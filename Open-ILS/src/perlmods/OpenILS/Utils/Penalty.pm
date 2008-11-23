package OpenILS::Utils::Penalty;
use strict; use warnings;
use DateTime;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Cache;
use OpenSRF::Utils qw/:datetime/;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Const qw/:const/;
my $U = "OpenILS::Application::AppUtils";


# calculate and update the well-known penalties
sub calculate_penalties {
    my($class, $e, $user_id, $context_org) = @_;

    my $penalties = $e->json_query({from => ['actor.calculate_system_penalties',$user_id, $context_org]});

    for my $pen_obj (@$penalties) {

        next if grep { # leave duplicate penalties in place
            $_->{org_unit} == $pen_obj->{org_unit} and
            $_->{standing_penalty} == $pen_obj->{standing_penalty} and
            ($_->{id} || '') ne ($pen_obj->{id} || '') } @$penalties;

        if(defined $pen_obj->{id}) {
            $e->delete_actor_user_standing_penalty($pen_obj->{id}) 
                or return $e->die_event;

        } else {
            my $newp = Fieldmapper::actor::user_standing_penalty->new;
            $newp->$_($pen_obj->{$_}) for keys %$pen_obj;
            $e->create_actor_user_standing_penalty($newp)
                or return $e->die_event;
        }
    }

    return undef;
}

# any penalties whose block_list has an item from @fatal_mask will be sorted
# into the fatal_penalties set.  Others will be sorted into the info_penalties set
sub retrieve_penalties {
    my($class, $e, $user_id, $context_org, @fatal_mask) = @_;

    my $penalties = $e->search_actor_user_standing_penalty([
        {usr => $user_id, org_unit => $U->get_org_ancestors($context_org)},
        {flesh => 1, flesh_fields => {ausp => ['standing_penalty']}}
    ]);

    my(@info, @fatal);
    for my $p (@$penalties) {
        my $pushed = 0;
        if($p->standing_penalty->block_list) {
            for my $m (@fatal_mask) {
                if($p->standing_penalty->block_list =~ /$m/) {
                    push(@fatal, $p->name);
                    $pushed = 1;
                }
            }
        }
        push(@info, $p->name) unless $pushed;
    }

    return {fatal_penalties => \@fatal, info_penalties => \@info};
}

1;
