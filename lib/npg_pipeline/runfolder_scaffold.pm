package npg_pipeline::runfolder_scaffold;

use Moose::Role;
use File::Path qw/make_path/;
use File::Spec;
use Readonly;
use Carp;

our $VERSION = '0';

Readonly::Scalar my $OUTGOING_PATH_COMPONENT    => q[/outgoing/];
Readonly::Scalar my $ANALYSIS_PATH_COMPONENT    => q[/analysis/];
Readonly::Scalar my $LOG_DIR_NAME               => q[log];
Readonly::Scalar my $TILEVIZ_DIR_NAME           => q[tileviz];
Readonly::Scalar my $STATUS_FILES_DIR_NAME      => q[status];
Readonly::Scalar my $SHORT_FILES_CACHE_DIR_NAME => q[.npg_cache_10000];
Readonly::Scalar my $METADATA_CACHE_DIR_NAME    => q[metadata_cache_];

sub create_analysis_level {
  my $self = shift;

  my @dirs = (
               $self->archive_path(),
               File::Spec->catdir($self->archive_path(), $SHORT_FILES_CACHE_DIR_NAME),
               $self->status_files_path(),
               $self->qc_path(),
               File::Spec->catdir($self->qc_path(), $TILEVIZ_DIR_NAME),
             );

  if ($self->is_indexed()) {
    foreach my $position ($self->positions()) {
      if ($self->is_multiplexed_lane($position)) {
        push @dirs, File::Spec->catdir($self->recalibrated_path(), q{lane} . $position);
        my $lane_dir = $self->lane_archive_path($position);
        push @dirs, $lane_dir;
        push @dirs, File::Spec->catdir($lane_dir, $SHORT_FILES_CACHE_DIR_NAME);
        push @dirs, $self->lane_qc_path($position);
      }
    }
  }

  my @errors = $self->make_dir(@dirs);
  return {'dirs' => \@dirs, 'errors' => \@errors};
}

sub create_top_level {
  my $self = shift;

  my @info = ();
  my @dirs = ();
  my $path;

  ######
  # The directory names for paths are hardcoded here. Primary definitions for
  # them are located in a number of tracking roles. These definitions should
  # be made available in tracking so the they can be used here.
  #
  if (!$self->has_intensity_path()) {
    $path = File::Spec->catdir($self->runfolder_path(), q{Data}, q{Intensities});
    if (!-e $path) {
      push @info, qq{Intensities path $path not found};
      $path = $self->runfolder_path();
    }
    $self->_set_intensity_path($path);
  }
  push @info, 'Intensities path: ', $self->intensity_path();

  if (!$self->has_basecall_path()) {
    $path = File::Spec->catdir($self->intensity_path() , q{BaseCalls});
    if (!-e $path) {
      push @info, qq{BaseCalls path $path not found};
      $path = $self->runfolder_path();
    }
    $self->_set_basecall_path($path);
  }
  push @info, 'BaseCalls path: ' . $self->basecall_path();

  if(!$self->has_bam_basecall_path()) {
    $path= File::Spec->catdir($self->intensity_path(), q{BAM_basecalls_} . $self->timestamp());
    push @dirs, $path;
    $self->set_bam_basecall_path($path);
  }
  push @info, 'BAM_basecall path: ' . $self->bam_basecall_path();

  if (!$self->has_recalibrated_path()) {
    $self->_set_recalibrated_path(File::Spec->catdir($self->bam_basecall_path(), 'no_cal'));
  }
  push @dirs, $self->recalibrated_path();
  push @info, 'no_cal path: ' . $self->recalibrated_path();

  my $metadata_cache_dir = $self->metadata_cache_dir_path();
  push @dirs, $metadata_cache_dir;
  push @info, "metadata cache path: $metadata_cache_dir";

  my @errors = $self->make_dir(@dirs);

  return {'msgs' => \@info, 'errors' => \@errors};
}

sub status_files_path {
  my $self = shift;
  my $apath = $self->analysis_path;
  if (!$apath) {
    croak 'Failed to retrieve analysis_path';
  }
  return File::Spec->catdir($apath, $STATUS_FILES_DIR_NAME);
}

sub metadata_cache_dir_path {
  my $self = shift;
  my $apath = $self->analysis_path;
  if (!$apath) {
    croak 'Failed to retrieve analysis_path';
  }
  return File::Spec->catdir($apath, $METADATA_CACHE_DIR_NAME . $self->id_run());
}

sub make_log_dir4names {
  my ($pkg, $analysis_path, @names) = @_;
  my @dirs = map { File::Spec->catdir(_log_path($analysis_path), $_) } @names;
  my @errors = __PACKAGE__->make_dir(@dirs);
  return {'dirs' => \@dirs, 'errors' => \@errors};
}

sub make_dir {
  my ($pkg, @dirs) = @_;

  my $err;
  make_path(@dirs, {error => \$err});
  my @errors = ();
  if (@{$err}) {
    for my $diag (@{$err}) {
      my ($d, $message) = %{$diag};
      if ($d eq q[]) {
        push @errors, "General error: $message";
      } else {
        push @errors, "Problem creating $d: $message";
      }
    }
  }
  return @errors;
}

sub path_in_outgoing {
  my ($pkg, $path) = @_;
  $path =~ s{$ANALYSIS_PATH_COMPONENT}{$OUTGOING_PATH_COMPONENT}xms;
  return $path;
}

sub future_path {
  my ($pkg, $d, $path) = @_;

  ($d && $path) or croak 'Definition and path arguments required' ;
  (ref($d) eq 'npg_pipeline::function::definition')
      or croak 'First argument should be a definition object';

  #####
  # The jobs that should be executed after the run folder is moved to
  # the outgoing directory have a preexec expression that check that
  # the path has changed to the outgoing directory. This fact is used
  # here to flag cases where the log directory pathe should change
  # from analysis to outgoing.
  #
  if ($d->has_command_preexec() &&
      $d->command_preexec() =~ /$OUTGOING_PATH_COMPONENT/smx) {
    $path = __PACKAGE__->path_in_outgoing($path);
  }

  return $path;
}

sub _log_path {
  my $analysis_path = shift;
  $analysis_path or croak 'Analysis path is needed';
  return File::Spec->catdir($analysis_path, $LOG_DIR_NAME);
}

no Moose::Role;

1;

__END__

=head1 NAME

npg_pipeline::runfolder_scaffold

=head1 SYNOPSIS

=head1 DESCRIPTION

Analysis run folder scaffolding.

=head1 SUBROUTINES/METHODS

=head2 create_analysis_level

Scaffolds the analysis directory.

=head2 create_top_level

Sets all paths needed during the lifetime of the analysis runfolder.
Creates any of the paths that do not exist.

=head2 status_files_path

A directory path to save status files to.

=cut

=head2 make_dir

Creates directories listed in the argiment list, creates intermwdiate directories
if they do not exist. Returns a list of errors, which, if all commands succeed,
is empty. Can be called both as an instance and a class method.

  my @errors = $scaffold->make_dir(qw/first second/);

=head2 metadata_cache_dir_path

=head2 make_log_dir4names

=head2 path_in_outgoing

Given a path in analysis directory changes it to outgoing directory.

=head2 future_path

If the job will run in the outgoing directory, a path in analysis directory
is changed to a path in outgoing directory.

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item Moose

=item namespace::autoclean

=item File::Path

=item File::Spec

=item Readonly

=item Carp

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

=over

=item Andy Brown

=item Marina Gourtovaia

=back

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2018 Genome Research Ltd

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
